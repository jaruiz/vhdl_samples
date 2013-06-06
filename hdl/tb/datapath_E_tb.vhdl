--##############################################################################
-- datapath_E_tb.vhdl -- Demonstration TB for floating point ALU:
--
-- This TB will feed the ALU a series of inputs while at the same time verifying
-- that the outputs are valid to within a few PPMs.
-- The error threshold is defined as constant ERROR_THRESHOLD_PPM. Declare it to
-- be under 14 to see some actual precision errors.
--
-- This test bench is for demonstration; it includes only a few input values
-- and does no real effort to catch errors.
--
-- NOTE: we define the operation error as abs((R - C)/R) and measure it in PPMs
-- (parts per million). This is a very crude measure of error but it's all I 
-- have time to do right now.
-- Note that we measure the PPMs in integer units; we need more resolution.
--##############################################################################

--#### Simulation utility package ##############################################

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

use work.datapath_pkg.all;


package datapath_tb_pkg is

-- Simulation clock period; arbitrary since this is a functional simulation.
constant T : time := 100 ns;

-- Totally arbitrary error threshold.
-- FIXME this threshold should be computed from the FP parameters and should
-- be different for MUL and ADD operations.
constant ERROR_THRESHOLD_PPM : integer := 15;

-- Data types employed by the result queues.

-- The result queue will be a simple FIFO which rolls 1 position each clock 
-- cycle. The last element of the queue (highest index) is the fifo output. This
-- element must be compared to the output of the UUT, but only when its 'valid'
-- field is '1'. Otherwise, the UUT is idle in this clock cycle and its output
-- is ignored along with the output of the queue.
-- The UUT has idle cycles when the load_a input is left inactive. These idle
-- cycles propagate through the pipeline.

type result_t is 
record
    -- '1' when this data is initialized and valid.
    valid :                 std_logic;
    -- Expected value.
    expected :              real;
    -- Error in PPM.
    error :                 integer;        
end record result_t;

type result_queue_t is array(integer range <>) of result_t;

-- Utility functions -----------------------------------------------------------

-- Put result for a given test vector in queue so that it can be checked later
procedure update_result_queue(signal q: inout result_queue_t; r: real; c: std_logic);
-- Compare last element of the result queue to uut output, raise warning if
-- difference is above arbitrary threshold. Returns error in PPM.
function verify_result(signal q: result_queue_t; computed: real; txt: string) return integer;

-- Convert VHDL real number to our binary representation
function real_to_word(r: real) return word_t;
-- Convert binary word in our FP format to VHDL real number
function word_to_real(w: word_t) return real;

end;

package body datapath_tb_pkg is

--------------------------------------------------------------------------------
procedure update_result_queue(signal q: inout result_queue_t; r: real; c: std_logic) is
begin
    q(1 to q'high) <= q(0 to q'high-1);
    q(0).expected <= r;
    q(0).valid <= c;
end procedure update_result_queue;

--------------------------------------------------------------------------------
function verify_result(signal q: result_queue_t; computed: real; txt: string) return integer is
variable expected : real;
variable error_ppm : integer;
begin
    expected := q(q'high).expected;
    
    -- FIXME Error should be computed in floating point. 
    -- This computation gives wrong results for very small errors. We're only
    -- interested in catching large errors (>10 ppm or so) so we can use it
    -- for the time being.
    if q(q'high).valid='1' and expected/=0.0 then
        error_ppm := integer((abs(expected - computed)/expected)*1.0e6);
    else
        error_ppm := 0;
    end if;

    assert error_ppm <= ERROR_THRESHOLD_PPM
    report txt& ": "& 
           "expected "& real'image(expected) &
           ", got "& real'image(computed) &
           " (relative error = "& integer'image(error_ppm) & " PPM)"
    severity warning;

    return error_ppm;
end function verify_result;

--------------------------------------------------------------------------------
function real_to_word(r: real) return word_t is
variable ex, mant : real;
variable f : float_t;
variable w : word_t;
variable ar : real;
begin
    if r < 0.0 then
        f.s := to_unsigned(1, 1);
        ar := -r;
    else
        f.s := to_unsigned(0, 1);
        ar := r;
    end if;
    
    ex := floor(log2(ar));
    mant := (ar /(2**ex))*real(P);
    f.e := to_unsigned(integer(ex)+EE, E);
    f.m := to_unsigned(integer(mant), M);
    w := float_to_word(f);
    return w;
end function real_to_word;

--------------------------------------------------------------------------------
function word_to_real(w: word_t) return real is
variable f : float_t;
variable r : real;
variable ex, mant, sg : real;
begin
    f := word_to_float(w);
    ex := real(to_integer(f.e)-EE);
    mant := real(to_integer(f.m))/real(P);
    sg := 1.0;
    r := sg * (2**ex) * mant;
    if f.s=1 then
        return -r;
    else
        return r;
    end if;
end function word_to_real;

end datapath_tb_pkg;


--#### Simulation test bench ###################################################

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.txt_util.all;
use work.datapath_pkg.all;
use work.datapath_tb_pkg.all;


entity datapath_E_tb is
end datapath_E_tb;


architecture tb0 of datapath_E_tb is

-- Interface to UUT ------------------------------------------------------------
signal data_a, data_b :     word_t;
signal sum_out :            word_t;
signal prod_out :           word_t;
signal start :              std_logic;
signal clk :                std_logic := '0';
signal reset :              std_logic := '0';

-- Signals used in the simulation display
signal a, b :               real;
signal sum, product :       real;

-- Simulation control ----------------------------------------------------------
-- Raised when the test is finished. Once raised, the clock will stop and no 
-- further input changes will happen, whereupon the simulator will stop.
signal test_done :          std_logic := '0';

-- Queues with the expected adder and multiplier results.
-- These queues replicate the UUT latencies for easy result verification.
signal add_result_queue :   result_queue_t(0 to 3);
signal mul_result_queue :   result_queue_t(0 to 2);

signal add_error :          integer;
signal mul_error :          integer;

-- Stimulus table & related stuff ----------------------------------------------

type stimulus_t is
record
    a :                     real;
    b :                     real;
end record stimulus_t;

type stim_vector_t is array(integer range <>) of stimulus_t;

constant stim_vector : stim_vector_t(1 to 5) := (
        (0.3,           0.3),
        (0.333333,      3.0),
        (0.1234,        -0.5678),
        (0.00001,       0.00001),
        (100.3,         -0.3)
    );

    
begin

uut : entity work.datapath_E port map (
    clk =>          clk,
    reset =>        reset,
    
    data_a_in =>    data_a,
    data_b_in =>    data_b,
    sum_out =>      sum_out,
    product_out =>  prod_out,
    start =>        start
);

clock_source:
process(test_done, clk)
begin
  if test_done='0' then
    clk <= not clk after T/2;
  end if;
end process clock_source;

feed_test_data:
process
variable i : integer;
begin
    -- Reset the UUT
    reset <= '1';
    start <= '0';
    wait for T;
    reset <= '0';
    
    print("Testing ALU inputs, watch out for assertion messages...");
    
    -- Feed all 
    for i in 1 to stim_vector'length loop
        data_a <= real_to_word(stim_vector(i).a);
        data_b <= real_to_word(stim_vector(i).b);
        start <= '1';
        wait for T;
    end loop;
    start <= '0';
   
    -- Wait a few clock cycles so that all ongoing operations have time to finish
    wait for T * 8;
    
    print("Done.");

    test_done <= '1';
    wait;
end process feed_test_data;


verify_results:
process(clk)
variable dummy, ob, a, b, r : real;
begin
    if clk'event and clk='1' then
        -- Use the dummy var to prevent Modelsim from optimizing away signals
        -- we want to display in the wave window (if there's a flag for that
        -- I could not find it).
        dummy := a;
        dummy := b;
        dummy := sum;
        dummy := product;
        
        a := word_to_real(data_a);
        b := word_to_real(data_b);
    
        update_result_queue(add_result_queue, a + b, start);
        add_error <= verify_result(add_result_queue, 
                        word_to_real(sum_out),
                        "Wrong adder output");
        
        update_result_queue(mul_result_queue, a * b, start);
        mul_error <= verify_result(mul_result_queue, 
                        word_to_real(prod_out),
                        "Wrong multiplier output");
    end if;
end process verify_results;

-- These signals are only used in the simulation display
a       <= word_to_real(data_a);
b       <= word_to_real(data_b);
sum     <= word_to_real(sum_out);
product <= word_to_real(prod_out);


end tb0;
