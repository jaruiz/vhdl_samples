--------------------------------------------------------------------------------
-- dds.vhdl -- Piecewise phase-to-amplitude DDS with sine and cosine outputs.
--
--------------------------------------------------------------------------------
-- Approximates the sine function by NUM_SLICES straight-line segments.
-- Assumes a system clock freq at least 2 times faster than the sampling rate, 
-- therefore we have 2 cycles to compute each output, or pair of outputs in 
-- this case.
-- 
-- Uses the clock-to-sample-rate factor of 2 to compute both sine and cosine 
-- using the same basic hardware (tables, multiplier, adders) in 2 clock cycles.
--
-- The phase-to-amplitude conversion is done by using a LUT on the phase value 
-- truncated to PHASE_TRUNC_WIDTH bits (defined as 'P' in ref. [1], page 51).
-- The truncated phase is split in two fields: the MSBs are the index of the
-- phase slice and the remaining bits are the 'offset' into the slice.
-- Thus, the simplified expression of the amplitude computation is:
--
--   Amplitude = base_slice[slice_index] + slope_slice[slice_index] * offset
--
-- (In actual practice, both the amplitude and the slope need to be scaled).
--
-- Note that the module does not use any block RAM -- the constant tables are 
-- combinational. This is cheap but hurts the clock rate badly.
-- If the DDS was large enough to be worth using a BRAM on it, with a bit of
-- pipelining the clock rate would improve a lot.
--
-- This module is meant for demonstration purposes only; it's not validated nor
-- fully optimized.
--------------------------------------------------------------------------------
-- Known bugs and oddities
-- 
-- 1.-  The generic values should be validated with assertions but aren't.
-- 2.-  Sync signals are valid for the *next* sample, not the present sample. 
-- 3.-  The tables used should be reduced to quarter cycle tables for a strong 
--      saving of LUTs, specially if we need more than a few phase slices.
-- 4.-  Use of VHDL features that are often not fully or consistently supported
--      across synthesis tools (e.g. real variable computations in synth time)
--      should be more thoroughly analyzed or at least tried on real hardware.
--------------------------------------------------------------------------------
-- REFERENCES:
-- [1] DDS: A Tool for Periodic Wave Generation (Part 1)
--     http://www.echelonembedded.com/dsphwlab/files/DDS_Lab_PDFs/DDS1.pdf
--------------------------------------------------------------------------------
-- VHDL sample -- not for actual use.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.txt_util.all;
use work.fixed_pkg.all;

entity dds is
    generic (
        DDS_SAMPLE_WIDTH : natural      := 12;
        SLOPE_WIDTH : natural       := 10;
        PHASE_ACC_WIDTH : natural   := 32; -- >= PHASE_TRUNC_WIDTH, >= 16
        PHASE_TRUNC_WIDTH : natural := 13; -- = log2(NUM_SLICES) + 6
        NUM_SLICES : natural        := 32  -- >= 8, power of 2
    );
    port ( 
        clk                     : in std_logic; -- global clock
        reset                   : in std_logic; -- global reset
        -- amount added to phase acc each sample cycle
        phase_delta             : in unsigned(PHASE_ACC_WIDTH-1 downto 0);
        sample_sin_out          : out signed(DDS_SAMPLE_WIDTH-1 downto 0);
        sample_cos_out          : out signed(DDS_SAMPLE_WIDTH-1 downto 0);
        sample_valid            : out std_logic;
        -- phase point sync flags; behaviour undefined yet 
        sync                    : out std_logic_vector(3 downto 0)
    );
end dds;

--------------------------------------------------------------------------------
-- Unoptimized, straight implementation of a piecewise DDS. Uses the same 
-- nomenclature as in document [1].
--
-- The phase approximation is PHASE_TRUNC_WIDTH bits long. This is split in two 
-- parts, a 'slice' (high log2(NUM_SLICES) bits) and a 'remainder' (remaining 
-- low bits), used as table indices. 
--------------------------------------------------------------------------------
architecture piecewise of dds is

-- The phase approximation which is PHASE_TRUNC_WIDTH bits wide will be used 
-- as input to a LUT. The index will be split in two parts:
-- The MSBs will determine which 'slice' of the phase circle we're in...
constant SLICE_INDEX_WIDTH : natural := log2(NUM_SLICES);
-- ...and the remaining bits will tell us how far into the slice.
constant SLICE_REM_WIDTH : natural := PHASE_TRUNC_WIDTH - SLICE_INDEX_WIDTH;


---- Local data types and (synthesizable) functions ----------------------------
-- These might as well go into a package, except they are only used here.

subtype base_t is signed(DDS_SAMPLE_WIDTH-1 downto 0);
subtype slope_t is signed(SLOPE_WIDTH-1 downto 0);

-- Phase-to-sin_base ROM.
-- Holds the 'base' value for each slice of the sine function: the value of
-- the function at the leftmost point of the slice.
type PtB_rom_t is array (natural range <>) of base_t;

-- Phase-to-slope ROM.
-- Holds the slope of the line that approximates the sine function at each 
-- phase slice. Fractional format.
type PtS_rom_t is array (natural range <>) of slope_t;

-- Build phase-to-sin_base look up table.
function build_base_table(slices: natural) return PtB_rom_t is
variable table : PtB_rom_t(0 to slices-1);
variable slice_base, i : integer;
variable rads_per_slice : real := 2.0 * 3.1415926 / real(slices);
variable scale : real := real(2**(DDS_SAMPLE_WIDTH-1));
begin
    for i in 0 to slices-1 loop
        -- The 'slice base' is the value f the leftmost point of the slice.
        slice_base := integer(floor(scale * sin(real(i) * rads_per_slice)));
        
        table(i) := to_signed(slice_base, DDS_SAMPLE_WIDTH);
    end loop;
    
    return table;
end function build_base_table;

-- Build phase-to-slope look up table.
function build_slope_table(base_table: PtB_rom_t) return PtS_rom_t is
variable table : PtS_rom_t(0 to base_table'high);
variable slice_base : integer;
variable next_slice_base : integer;
variable delta : integer;
variable i, j : integer;
variable max_delta : integer := 0;
begin
    for i in 0 to base_table'high loop
        -- The 'slice base' is the value f the leftmost point of the slice.
        slice_base := to_integer(base_table(i));
        -- The slope can be computed by looking at the base of the next slice.
        j := (i+1) mod base_table'length;
        next_slice_base := to_integer(base_table(j));
        
        -- We compute the delta for this slice...
        delta := next_slice_base - slice_base;
        -- ...and keep track of the biggest absolute delta seen soo far.
        if abs(delta) > max_delta then
            max_delta := abs(delta);
        end if;
        
        -- The slope table is actially a *delta* table; the division by the 
        -- slice width is done later, by truncating the slope product.
        table(i) := to_signed(delta, SLOPE_WIDTH);
    end loop;

    -- Make sure the slope table has not been truncated due to insufficient
    -- precision. This will happen when the delta does not fit in the table.
    assert max_delta < 2**(SLOPE_WIDTH-1)
    report "Slope precision ("& str(SLOPE_WIDTH)& 
           " bits) is insufficient for current signal scale."
    severity failure;

    
    return table;
end function build_slope_table;
--------------------------------------------------------------------------------

-- Compute the initialization constants for the base and slope tables.
-- NOTE: both the base and the slope tables are 'full' tables, holding the 
-- values for a full period of the sine function. They should be reduced to 
-- quarter-cycle tables in further versions.
constant BASE_TABLE : PtB_rom_t(0 to NUM_SLICES-1) := build_base_table(NUM_SLICES);
constant SLOPE_TABLE : PtS_rom_t(0 to NUM_SLICES-1) := build_slope_table(BASE_TABLE);

-- ptb_rom: Phase-to-base lookup table.
signal ptb_rom :         PtB_rom_t(0 to NUM_SLICES-1) := BASE_TABLE;
-- pts_rom: phase-to-slope lookup table.
signal pts_rom :         PtS_rom_t(0 to NUM_SLICES-1) := SLOPE_TABLE;

-- phase_acc: DDS phase accumulator (N bits wide)
signal phase_acc :          unsigned(PHASE_ACC_WIDTH-1 downto 0);
-- phase: DDS phase information (accumulator truncated to P bits)
signal phase :              unsigned(PHASE_TRUNC_WIDTH-1 downto 0);
-- phase_slice : phase 'slice' within cycle
signal phase_slice :        unsigned(SLICE_INDEX_WIDTH-1 downto 0);
-- phase_quarter:
signal phase_quarter :      unsigned(1 downto 0);
-- phase_slice_prev : value of phase_quarter in the previous output sample  
signal phase_quarter_prev : unsigned(1 downto 0);  
-- phase_rem : phase point within phase slice.
-- Will be converted from unsigned to signed by zero-sign-extension.
signal phase_rem :          signed(SLICE_REM_WIDTH-1+1 downto 0);
-- sin_slope: slope of sine function at the present phase slice
signal sin_slope :          signed(SLOPE_WIDTH-1 downto 0);
-- phase_slice_mux: phase slice for SIN or COS, computed from phase-slice (i.e.
--      unmodified phase_slice for SIN, phase_slice + 64/4 for COS). Note that
--      the remainder is the same in both cases.
signal phase_slice_mux :    unsigned(SLICE_INDEX_WIDTH-1 downto 0);  
  
-- phase_markers: unregistered versions of sync outputs
signal phase_mark :         std_logic_vector(3 downto 0);

signal sin_base :           signed(DDS_SAMPLE_WIDTH-1 downto 0);
signal sin_value :          signed(DDS_SAMPLE_WIDTH-1 downto 0);
signal sin_fraction :       signed(DDS_SAMPLE_WIDTH-1 downto 0);
signal product :            signed(phase_rem'length+SLOPE_WIDTH-1 downto 0);
signal product_extended :   signed(DDS_SAMPLE_WIDTH+SLOPE_WIDTH-1 downto 0);

signal update_acc :         std_logic;
signal update_sine :        std_logic;
signal update_cosine :      std_logic;
 
begin


-- phase accumulator -- FIXME programmable reset value?
-- the acc updates once for every pair of samples, i.e. when state='1' (when
-- the phase has already been used to compute sine and cosine).
phase_acc_register:
process(clk)
begin
    if clk'event and clk='1' then
        if reset='1' then
            phase_acc <= (others => '0');
        else
            if update_acc='1' then
                phase_acc <= phase_acc + phase_delta;
            end if;
        end if;
    end if;
end process phase_acc_register;

-- get the current phase slice and remainder from the current phase acc value
phase <= unsigned(phase_acc(phase_acc'high downto phase_acc'high-PHASE_TRUNC_WIDTH+1));
phase_slice <= phase(SLICE_REM_WIDTH+SLICE_INDEX_WIDTH-1 downto SLICE_REM_WIDTH);
phase_rem <= signed('0' & phase(SLICE_REM_WIDTH-1 downto 0));


-- The tables are for the sine function; in order to use them to get the cosine,
-- all we need to do is take a phase slice that is a quarter of a full period 
-- ahead; since the table size is a power of 2, there's no approximation 
-- error here.
phase_slice_mux <= phase_slice when update_sine='1' else
                   phase_slice + (NUM_SLICES/4);


-- phase slice slope ROM: async, LUT based ROM
sin_slope <= signed(pts_rom(to_integer(phase_slice_mux)));
-- phase slice step ROM: async, LUT based ROM
sin_base <= signed(ptb_rom(to_integer(phase_slice_mux)));


-- Sine/cosine function approximation.
-- Compute height of straight segment in slice...
product <= (sin_slope * phase_rem); 
product_extended(product'high downto 0) <= product;
product_extended(product_extended'high downto product'high+1) <= (others => product(product'high));
-- ...and truncate it dropping the lowest SLICE_REM_WIDTH bits. This is the same
-- as dividing by the width of the slice.
sin_fraction <= product_extended(SLICE_REM_WIDTH+DDS_SAMPLE_WIDTH-1 downto SLICE_REM_WIDTH); 
-- Finally add it to slice base point.
sin_value <= sin_base + sin_fraction; 

-- output sample regs, which update in alternate cycles
output_sample_registers:
process(clk)
begin
    if clk'event and clk='1' then
        if update_sine='1' then
            sample_sin_out <= sin_value;
        end if;
        if update_cosine='1' then
            sample_cos_out <= sin_value;
        end if;
    end if;
end process output_sample_registers;

-- sync signals have no clear purpose yet; for the time being, they're going to 
-- assert in one-hot fashion for phases 0,90,180 and 270 (deg). We just need to
-- look at the phase slice value for those phases; we keep the previous 
-- slice in a register and look for certain transitions.

-- register the previous phase values...
previous_phase_reg:
process(clk)
begin
    if clk'event and clk='1' then
        phase_quarter_prev <= phase_quarter;
    end if;
end process;

phase_quarter <= phase_slice(phase_slice'high downto phase_slice'high-1);

-- ... then look for expected transitions at 0,90,180 and 270 degs
phase_mark(0) <= '1' when phase_quarter_prev="11" and phase_quarter="00"
                     else '0';
phase_mark(1) <= '1' when phase_quarter_prev="00" and phase_quarter="01"
                     else '0';
phase_mark(2) <= '1' when phase_quarter_prev="01" and phase_quarter="10"
                     else '0';
phase_mark(3) <= '1' when phase_quarter_prev="10" and phase_quarter="11"
                     else '0';
  
-- delay the sync flags, so they're properly aligned with the signal value
sync_marks_reg:
process(clk)
begin
    if clk'event and clk='1' then
        sync <= phase_mark;
    end if;
end process;
  
-- the state machine has only two states which are encoded in 2 flags: 
-- update_sine and update_acc.
-- Basically, sine and cosine values are alternately computed and the output 
-- is valid when the cosine is updated.
control_state_machine:
process(clk)
begin
  if (clk'event and clk='1') then
    if reset='1' then 
      update_sine <= '0';
      update_cosine <= '0';
      sample_valid <= '0';
      update_acc <= '1';
    else
      update_sine <= update_acc;
      update_cosine <= update_sine;
      update_acc <= update_sine;
      sample_valid <= update_cosine;
    end if;
  end if;
end process;  


end piecewise;
