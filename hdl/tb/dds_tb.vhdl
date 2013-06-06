--------------------------------------------------------------------------------
-- dds_tb.vhdl : basic test bench for DDS module.
--------------------------------------------------------------------------------
-- This TB will drive the DDS to produce a sample every 2 clock cycles. In
-- actual operation, the DDS will have to produce a sample each N cycles where
-- N is the folding factor, possibly longer that 2 cycles.
--------------------------------------------------------------------------------
-- 'Visual' test bench: only useful as a means to see if the UUT does something
-- at all resembling its intended purpose. 
-- It will run the DDS with two frequencies.
-- Does not try to catch any errors automatically.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity dds_tb is
end dds_tb;

architecture behavior of dds_tb is 

--------------------------------------------------------------------------------
-- simulation parameters

-- T: simulation clock period. Not relevant for this functional simulation.
constant T : time := 20 ns;

-- Simulation log file (will be a .m script)
--file log_file: TEXT open write_mode is "fir_log.m";
-- do_log_y: true when the output should be logged.
signal do_log_y :           boolean := false;


-- DDS parameters -- note that they are NOT independent.
constant SAMPLE_WIDTH               : natural := 12;
constant PHASE_ACC_WIDTH            : natural := 32;
constant PHASE_TRUNC_WIDTH          : natural := 13;
constant NUM_SLICES                 : natural := 32;

--------------------------------------------------------------------------------

signal sample_sin :         signed(SAMPLE_WIDTH-1 downto 0);
signal sample_cos :         signed(SAMPLE_WIDTH-1 downto 0);
signal phase_delta :        unsigned(PHASE_ACC_WIDTH-1 downto 0);
signal sync :               std_logic_vector(3 downto 0);
signal sample_valid :       std_logic;
signal done :               std_logic := '0';
signal reset :              std_logic := '0';
signal clk :                std_logic := '0';

begin

    inst_dds: entity work.dds 
    generic map (
        SAMPLE_WIDTH                => SAMPLE_WIDTH,
        PHASE_ACC_WIDTH             => PHASE_ACC_WIDTH,
        PHASE_TRUNC_WIDTH           => PHASE_TRUNC_WIDTH,
        NUM_SLICES                  => NUM_SLICES       
    )
    port map(
      clk               => clk,
      reset             => reset,
      phase_delta       => phase_delta,
      sample_sin_out    => sample_sin,
      sample_cos_out    => sample_cos,
      sample_valid      => sample_valid,
      sync              => sync
    );


    ---------------------------------------------------------------------------
    -- clock: free running clock, plus end-of-simulation checkpoint
    clock:
    process(done, clk)
    begin
        if done = '0' then
            clk <= not clk after T/2;
        else
            assert (done='0') report "end of simulation" severity failure;
        end if;
    end process clock;

    drive_uut:
    process
    variable i : integer;
    begin
    
        reset <= '1';
        wait for T;
        reset <= '0';
        
        phase_delta <= to_unsigned(16#00080347#, PHASE_ACC_WIDTH);
        -- drive the DDS for a lot of 4-cycle sample periods
        for i in 0 to 50000 loop
            wait for T;
        end loop;
        
        phase_delta <= to_unsigned(16#000f0347#, PHASE_ACC_WIDTH);
        -- drive the DDS for a lot of 4-cycle sample periods
        for i in 0 to 50000 loop
            wait for T;
        end loop;
        
        done <= '1';
        wait;
        
    end process drive_uut;

END;
