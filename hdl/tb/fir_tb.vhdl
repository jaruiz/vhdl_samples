--------------------------------------------------------------------------------
-- fir_tb.vhdl -- Test bench for the fir.vhdl FIR filter module.
--------------------------------------------------------------------------------
--
-- Note that this test bench is mostly a visual demonstration and not a real 
-- test bench. It does not test for operational boundaries (e.g. sampling 
-- period) and relies on an external Matlab script to validate its output.
--
-- This test bench logs the filter input and output to a 'fir_log.m' 
-- Matlab script file which in turn is then run by a verification script.
-- A FIR is simple enough that it can be easily verified in VHDL. Yet, using 
-- an external matlab script is perhaps more illustrative of the kind of thing 
-- we might do to test a more complex system. This can be automated to a very 
-- large extent using simulation scripts.
-- Note that the Matlab verification script is very minimalistic and is only 
-- useful as a proof of concept, and a very simple one at that.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fixed_pkg.all;
use std.textio.all;
use work.txt_util.all;


entity fir_tb is
end fir_tb;


architecture tb0 of fir_tb is

---- Define some simulation parameters -----------------------------------------

-- Number of coefficients in the filter impulse response.
constant NUM_COEFS : integer := 64;
-- Simulated clock period -- irrelevant in this behavioral simulation.
constant T : time := 100 ns;

---- Compute some simulation constants -----------------------------------------

-- Minimum sampling period -- this is actually a parameter of the module.
constant MIN_SAMPLE_PERIOD : integer := NUM_COEFS + 0;
-- Sampling period to be used in the test.
constant SAMPLE_PERIOD : integer := MIN_SAMPLE_PERIOD;

-- Simulation log file (will be a .m script)
file log_file: TEXT open write_mode is "fir_log.m";

-- Interface to UUT ------------------------------------------------------------
signal x :                  sample_t;
signal x_valid :            std_logic := '0';
signal y :                  signed((SAMPLE_WIDTH*2)-1 downto 0);
signal y_valid :            std_logic;
signal clk :                std_logic := '1';
signal reset :              std_logic := '0';

constant OUTPUT_WIDTH : integer := 23;
signal y_slice :            signed(OUTPUT_WIDTH-1 downto 0);
signal yr :                 real;

-- Simulation control ----------------------------------------------------------
-- test_done: Raised when the test is finished. Once raised, the clock will stop
-- and no further input changes will happen, whereupon the simulator will stop.
signal test_done :          std_logic := '0';
-- do_log_y: true when the output should be logged.
signal do_log_y :           boolean := false;

-- Stimulus table & related stuff ----------------------------------------------

type t_real_vector is array(integer range <>) of real;

function build_stim_signal(num_samples: integer) return t_real_vector is
variable x : t_real_vector(0 to num_samples-1);
variable k : real;
begin

    k := 0.5;
    for i in 0 to num_samples-1 loop
        x(i) := k;
        k := k / 2.0;
        if abs(k) < 0.125 then
            if k > 0.0 then
                k := -0.5;
            else
                k := 0.5;
            end if;
        end if;
    end loop;

    return x;
end function build_stim_signal;

-- Build some arbitrary impulse reponse vector for the tests.
function build_h(order: integer; mode: integer := 0) return t_coef_table is
variable h : t_coef_table(0 to order-1);
variable k : real;
begin

    case mode is 
    when 0 =>
        h := (others => 0.0);
        h(0) := 0.5;
    when 1 =>
        h := (others => 0.0);
        h(order-1) := 0.5;
    when 2 =>
        -- We want an h[n] that has positive and negative values and with no null 
        -- values. We build some such signal with no further constraints.
        k := 0.9;
        for i in 0 to order-1 loop
            h(i) := k;
            k := k * (-0.9);
        end loop;
    when others =>
        assert 1 = 0
        report "Invalid mode for function build_h."
        severity failure;
    end case;

    return h;
end function build_h;

-- Create the input test signal...
constant stim_signal : t_real_vector(0 to NUM_COEFS*4-1) := build_stim_signal(NUM_COEFS*4);
-- ...and the impulse response vector.
constant FIR_COEFS : t_coef_table(0 to NUM_COEFS-1) := build_h(NUM_COEFS,2);

-- Print a real number to a file -- crude hack, improve!
procedure print(file f: text; x: real) is
variable msg_line: line;
begin
    write(msg_line, x, right, 16);
    writeline(f, msg_line);
end procedure print;

-- Wait for a given number of clock EDGES. 
procedure wait_for_clk_edge(n: natural := 1) is
begin
    -- FIXME there should be a timeout somewhere here.
    for i in 0 to n-1 loop
        wait until clk'event and clk='1';
    end loop;
end procedure wait_for_clk_edge;


--------------------------------------------------------------------------------

begin

uut : entity work.fir
generic map (
    COEFS =>        FIR_COEFS
)
port map (
    clk =>          clk,
    reset =>        reset,

    x =>            x,
    x_valid =>      x_valid,
    y =>            y,
    y_valid =>      y_valid
);

-- This is the clock generator. It will stop as soon as test_done='1', at which 
-- moment the simulation will stop automatically.
clock_source:
process(test_done, clk)
begin
  if test_done='0' then
    clk <= not clk after T/2;
  end if;
end process clock_source;

-- Main process: 
feed_test_data:
process
variable i : integer;
variable product : integer;
variable m, r : integer;
begin
    print(log_file, "% Simulation log for module fir.vhdl -- created by fir_tb.vhdl/fir_tb.do.");
    print(log_file, "% Don't use this file directly, use fir_test.m instead.");
    print(log_file, "");

    -- Log some simulation parameters -- sample widths, mosty.
    print(log_file, "% Some simulation parameters.");
    print(log_file, "sample_width = "& str(SAMPLE_WIDTH)& ";");
    print(log_file, "sample_integer_part = "& str(SAMPLE_INTEGER_PART)& ";");
    print(log_file, "output_truncated_width ="& str(OUTPUT_WIDTH)& ";");
    print(log_file, "");

    -- Log the h[n] as a real vector...
    print(log_file, "% hr : Filter impulse response, non-quantized.");
    print(log_file, "hr = [");
    for i in 0 to NUM_COEFS-1 loop
        print(log_file, FIR_COEFS(i));
    end loop;
    print(log_file, "];");
    print(log_file, "");
    -- ...and as a quantized signed integer vector. Having both will help catch
    -- quantization errors.
    print(log_file, "% h : Filter impulse response, quantized.");
    print(log_file, "h = [");
    for i in 0 to NUM_COEFS-1 loop
        print(log_file, str(to_integer(real_to_sample(FIR_COEFS(i))))& ",");
    end loop;
    print(log_file, "];");
    print(log_file, "");

    -- Now log the input signal.
    print(log_file, "% x : Test input signal, quantized.");
    print(log_file, "x = [");
    for i in 0 to stim_signal'high loop
        print(log_file, str(to_integer(real_to_sample(stim_signal(i))))& ",");
    end loop;
    print(log_file, "];");
    print(log_file, "");

    -- Ok, here's where the test begins. Note we wait for absolute periods of
    -- time and NOT for clock edges; all signal transitions will be aligned
    -- to the active clock edge, and we rely on the initial clk signal value
    -- for that. It would be better to synchronize everything to the active
    -- clock edge.

    -- We'll be logging the convolution result so print the beginning of the
    -- signal declaration to the m-file:
    print(log_file, "% y : Filter output, truncated to "& str(OUTPUT_WIDTH)& " bits.");
    print(log_file, "y = [");

    -- Reset the UUT
    reset <= '1';
    wait until clk'event and clk='1';
    reset <= '0';

    -- Clear the delay buffer using a zero input signal.
    for i in 0 to NUM_COEFS-1 loop
        x <= (others => '0');
        x_valid <= '1';
        wait_for_clk_edge;
        x_valid <= '0';
        wait_for_clk_edge(SAMPLE_PERIOD-1);
        -- Wait a little longer than necessary to emphasize that the sampling 
        -- period is a minimum and can be extended as needed.
        wait_for_clk_edge(4);
    end loop;

    -- Enable filter output logging. With this, we 'clip' the output signal log
    -- to the size convolution of the input signal and the impulse response,
    -- for easier validation.
    do_log_y <= true;
    
    -- Feed the test signal in.
    for i in 0 to stim_signal'high loop
        -- Assert x_valid for a cycle while putting the input sample in x...
        x <= real_to_sample(stim_signal(i));
        x_valid <= '1';
        wait_for_clk_edge;
        -- ...then wait for the rest of the sampling period with x_valid 
        -- deasserted.
        x_valid <= '0';
        x <= (others => '0');
        wait_for_clk_edge(SAMPLE_PERIOD-1);

        -- This assertion is only meant to prevent Modelsim from optimizing
        -- away signal yr, without tinkering with command line options.
        assert abs(yr) < 1.0
        report "Scale error in filter output -- bug in the test bench."
        severity warning;

    end loop;

    -- As soon as the input stream stops, the output stream will too.
    -- Feed a stream of zeros so that the last convolution has time to complete.
    -- This is for display purposes only.
    -- This stream is long enough to let the filter complete the convolution of
    -- the whole input signal vector. 
    for i in 0 to (NUM_COEFS-1) - 1 loop
        x <= (others => '0');
        x_valid <= '1';
        wait_for_clk_edge;
        x_valid <= '0';
        wait_for_clk_edge(SAMPLE_PERIOD);
    end loop;
    -- End of the log, 'close' output signal declaration.
    do_log_y <= false; -- Stop logging the filter output.
    print(log_file, "];");
    print(log_file, "");

    -- Wait for a few cycles so that all ongoing operations have plenty of time
    -- to finish before terminating the simulation. Output log is OFF by now.
    wait_for_clk_edge(NUM_COEFS + 8);

    -- Command clock process to stop, stopping the simulation.
    test_done <= '1';

    wait;
end process feed_test_data;


log_filter_output:
process
begin
    while true loop
        wait until clk'event and clk='1';
        if do_log_y and y_valid='1' then
            print(log_file, str(to_integer(y_slice))& ",");
        end if;
    end loop;
end process log_filter_output;


-- Truncate the filter output, taking the MSBs; this way we don't have to deal
-- with numbrs larger than 32 bits.
-- Bear in mind the FIR module does no truncation internally
y_slice <= y(y'high downto y'high-OUTPUT_WIDTH+1);
-- Convert the truncated output to real, for display only.
-- Note we scale the output for NUM_COEFS, because it is a summation.
-- Note too that we assume the output range is (-1..+1), and we account for
-- the duplicated sign bit.
yr <= real(to_integer(y_slice)) * real(NUM_COEFS) / real(2**(OUTPUT_WIDTH-1));


end tb0;
