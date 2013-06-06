--------------------------------------------------------------------------------
-- fir.vhdl -- FIR filter, fixed precision.
--------------------------------------------------------------------------------
-- This module is meant for demonstration purposes only -- it is not part of any
-- actual project nor has it ever been tested on actual hardware.
--------------------------------------------------------------------------------
-- Generics:
--
--  COEFS : Impulse response coefficient table as a vector of real numbers.
--          
--          Both the type (t_coef_table) and the quantization parameters are 
--          defined in package 'fixed_pkg'.
--------------------------------------------------------------------------------
-- Input/output ports:
--
-- clk :            Clock input, active at rising edge.
-- reset :          Synchronous reset, active high.
--
-- x_valid :        Asserted high for 1 cycle when port 'x' holds a valid input 
--                  sample. See below for assertion restrictions.
-- x :              Input data sample. 
-- y_valid :        Asserted high for 1 cycle when port 'y' holds a valid output
--                  sample.
--
-- The minimum sampling period (number of cycles between consecutive assertions 
-- of input x_valid) is NUM_COEFS. Assertion of x_valid with a shorter period 
-- will yield invalid results -- missing output samples, etc.
--
-- The input-to-output latency is NUM_COEFS+3.
--
-- Sample size and quantization parameters are defined in package 'fixed_pkg'.
--------------------------------------------------------------------------------
-- Features:
--
-- This FIR module will use the same memory block for both the filter 
-- coefficients (h[n]) and the delayed input (x*z^-i), by using both ports of 
-- the memory block. The code is vendor-agnostic and relies on RAM inference
-- only -- no module instantiations. 
-- This is meant to take maximum advantage of the bandwidth of the FPGA 
-- internal RAM.
-- This code has only been tested on Altera and Xilinx synthesis tools.
-- IMPORTANT: see note 1 below if your sample size is not <=16 or ==32.
--
-- There is no internal truncation of intermediate results -- any truncation 
-- and/or rescaling must be done by the parent module. 
-- The module uses a synchronous multiplier that will sinthesize into a 
-- dedicated multiplier block in those FPGA architectures that have them. 
-- Some of those architectures support dedicated, pipelined 
-- multiplier-accumulators (e.g. Xilinx DSP48 block) but no effort has been 
-- made to infer them. The accumulator will generally be sinthesized with 
-- regular fabric logic.
--
-- The filter is assumed NOT to be symmetric -- for symmetric filters an 
-- optimized structure should be used (one that adds values of x[-n] before
-- the product with h).
--
-- Preliminar synthesis results (16-bit samples, 128 coefficients):
-- 
-- Quartus 2, balanced; Cyclone-2 grade -7: 111 LEs, 1 M4K, 1 DSP-18 @ 154 MHz
-- ISE 9,     area;     Spartan-3 grade -5: 48 LUTs, 1 BRAM, 1 DSP-18 @ 160 MHz 
--------------------------------------------------------------------------------
-- Known BUGS:
--
--------------------------------------------------------------------------------
-- Notes: 
--
-- 1.-  Most architectures, including Cyclone and Spartan, do not support
--      24-bit-wide RAM ports -- a 24-bit wide port will actually use a 32-bit
--      word within the BRAM. The synth may be able to arrange several BRAMs 
--      in parallel if the filter is long enough, optimizing memory usage. 
--      Otherwise, you may be wasting a lot of RAM if your sample size does not 
--      match your target FPGA architecture. The same goes for multiplier width.
-- 2.-  This module will produce one output sample per input sample -- if the 
--      input stream stops, the output stream will too.
--      
--------------------------------------------------------------------------------
-- REFERENCES:
-- [1] Tips for vendor-agnostic BRAM inference:
--     http://www.danstrother.com/2010/09/11/inferring-rams-in-fpgas/
--------------------------------------------------------------------------------
-- VHDL sample -- not for actual use.
--------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fixed_pkg.all;

entity fir is
    generic (
        COEFS : t_coef_table := delta_coefs(128)
    );
    port (
        clk :               in std_logic;
        reset :             in std_logic;

        x :                 in signed(SAMPLE_WIDTH-1 downto 0);
        x_valid :           in std_logic;
        y :                 out signed((SAMPLE_WIDTH*2)-1 downto 0);
        y_valid :           out std_logic
    );
end fir;


architecture vendor_agnostic of fir is

---- Configuration constants ---------------------------------------------------

constant NUM_COEFS : integer := COEFS'length;
-- The RAM block must be long enough to hold h[n] and x[n] and its size will 
-- be rounded up to the nearest power of two, to simplify addressing.
constant BRAM_SIZE : integer := 2 * (2**log2(NUM_COEFS));
-- The accumulator will be long enough to hold all the intermediate results 
-- with no truncation.
constant ACC_WIDTH : integer := (SAMPLE_WIDTH * 2) + log2(NUM_COEFS);

---- Local data types ----------------------------------------------------------

-- Actual RAM address covering all the range.
subtype t_bram_addr is unsigned(log2(BRAM_SIZE)-1 downto 0);
-- Index for h[n] or x[n] -- covers half the RAM address range.
subtype t_coef_index is unsigned(log2(BRAM_SIZE)-2 downto 0);

-- Control bits that will be carried through all the pipeline stages.
type t_control is record
    clear_acc :     std_logic; -- Don't accumulate to previous ACC result.
    y_valid :       std_logic; -- Assert y_valid; used in last pipeline stage.
end record;

---- Pipeline stage 0 signals --------------------------------------------------
-- Stage 0 holds most of the control logic including the sample index counters.

signal p0_i_reg :           t_coef_index;
signal p0_n_reg :           t_coef_index;
signal p0_iz :              t_coef_index;
signal p0_j :               t_coef_index;

signal p0_control :         t_control;

-- BRAM interface signals; the synchronous BRAM is split across stages 0 and 1.
signal p0_bram_we :         std_logic;
signal p0_bram_port0_wr :   sample_t;
signal p0_bram_port0_addr : t_bram_addr;
signal p0_bram_port1_addr : t_bram_addr;


---- Pipeline stage 1 signals --------------------------------------------------

-- BRAM, initialized with the filter coefficients.
-- Part of the BRAM inference template; do not change! -- see reference [1].
shared variable p1_bram :   sample_table_t(0 to BRAM_SIZE-1) := 
                            h_to_bram(COEFS,SAMPLE_INTEGER_PART,SAMPLE_WIDTH,BRAM_SIZE);

signal p1_h :               sample_t;
signal p1_xz :              sample_t;                            
signal p1_control :         t_control;
                            
---- Pipeline stage 2 signals --------------------------------------------------

signal p2_h_reg :           sample_t;
signal p2_xz_reg :          sample_t;
signal p2_control :         t_control;

---- Pipeline stage 3 signals --------------------------------------------------

signal p3_product_reg :     signed((SAMPLE_WIDTH*2)-1 downto 0);
signal p3_product_sign :    std_logic;
signal p3_ext_product :     signed(ACC_WIDTH-1 downto 0);
signal p3_control :         t_control;

---- Pipeline stage 4 signals --------------------------------------------------

signal p4_control :         t_control;
signal p4_accumulator_reg : signed(ACC_WIDTH-1 downto 0);
signal p4_acc_feedback :    signed(ACC_WIDTH-1 downto 0);

---- State machine control signals ---------------------------------------------

signal p0_idle :            std_logic;
signal p0_end_of_loop :     std_logic;
signal p0_running_convolution : std_logic;
                           
begin

---- STAGE 0 -------------------------------------------------------------------

-- Main control logic and sample index registers.

-- The convolution is running:
-- a) The cycle a new X sample arrives (x_valid)...
-- b) ...and until the convolution loop is finished (not p0_idle).
p0_running_convolution <= (x_valid or (not p0_idle));

sample_index_registers:
process(clk)
begin
    if clk'event and clk='1' then
        if reset = '1' then
            p0_i_reg <= (others => '0');
            p0_n_reg <= (others => '0');
            p0_idle <= '1';
        else
            -- If we're running the convolution loop, increment the loop index,
            -- otherwise clear the index to be ready for the next convolution.
            if p0_running_convolution='1' and p0_end_of_loop='0' then
                p0_idle <= '0';
                p0_i_reg <= p0_i_reg + 1;
            else
                p0_i_reg <= (others => '0');
                p0_idle <= '1';
            end if;
        
            -- After the end of each convolution, 'shift' the X delay queue.
            if p0_i_reg = (NUM_COEFS-1) then
                p0_n_reg <= p0_n_reg + 1;
            end if;
        end if;
    end if;
end process sample_index_registers;

-- Asserted in the last cycle of a convolution. 
p0_end_of_loop <= '1' when p0_i_reg = (NUM_COEFS-1) else '0';

-- Clear acc at the last cycle of every convolution, and whenever the FIR is
-- idle.
p0_control.clear_acc <= p0_end_of_loop or (p0_idle and not x_valid);
-- The accumulator will hold the true output value after the last cycle of the
-- convolution.
p0_control.y_valid <= p0_end_of_loop;


---- STAGE 1 -------------------------------------------------------------------

-- Synchronous BRAM used for filter coefs AND input sample delay.

pipeline_stage1_registers: 
process(clk)
begin
    if clk'event and clk='1' then 
        p1_control <= p0_control;
    end if;
end process pipeline_stage1_registers;


p0_bram_port0_wr <= x;
p0_bram_we <= x_valid;
p0_iz <= p0_n_reg - p0_i_reg;
p0_bram_port0_addr <= '1' & p0_iz;

-- IMPORTANT: the 2-port BRAM is inferred using a template which is valid for
-- both Altera and Xilinx. Otherwise, the synth tools would infer TWO BRAMs 
-- instead of one.
-- This template is FRAGILE: for example, changing the order of assignments in 
-- process *_port0 will break the synthesis (i.e. 2 BRAMs again).
-- See a more detailed explaination in [1].

-- BRAM port 0 is read/write (i.e. same address for read and write)
fir_bram_port0:
process(clk)
begin
   if clk'event and clk='1' then
        if p0_bram_we='1' then
            p1_bram(to_integer(p0_bram_port0_addr)) := p0_bram_port0_wr;
        end if;
        p1_xz <= p1_bram(to_integer(p0_bram_port0_addr));
   end if;
end process fir_bram_port0;

-- Port 1 is read only
register_bank_bram_port1:
process(clk)
begin
   if clk'event and clk='1' then
        p1_h <= p1_bram(to_integer(p0_i_reg));
   end if;
end process register_bank_bram_port1;

-- End of BRAM inference template ----



---- STAGE 2 -------------------------------------------------------------------

-- Registered multiplier input

pipeline_stage2_registers: 
process(clk)
begin
    if clk'event and clk='1' then 
        p2_h_reg <= p1_h;
        p2_xz_reg <= p1_xz;
        p2_control <= p1_control;
    end if;
end process pipeline_stage2_registers;

---- STAGE 3 -------------------------------------------------------------------

-- Registered multiplier output (synchronous multiplier)

pipeline_stage3_registers: 
process(clk)
begin
    if clk'event and clk='1' then 
        p3_control <= p2_control;
    end if;
end process pipeline_stage3_registers;

-- This will usually be synthesized into a dedicated multiplier, part of a 
-- DSP block. 
synchronous_multiplier : 
process(clk)
begin
    if clk'event and clk='1' then 
        p3_product_reg <= p2_h_reg * p2_xz_reg;
    end if;
end process synchronous_multiplier;

p3_product_sign <= p3_product_reg(p3_product_reg'high);
p3_ext_product(p3_ext_product'high downto p3_product_reg'high+1) <= (others => p3_product_sign);
p3_ext_product(p3_product_reg'high downto 0) <= p3_product_reg;

---- STAGE 4 -------------------------------------------------------------------

-- Accumulator register

pipeline_stage4_registers: 
process(clk)
begin
    if clk'event and clk='1' then 
        p4_control <= p3_control;
    end if;
end process pipeline_stage4_registers;

-- When clear_acc is asserted, the accumulator will 'forget' its current value 
-- and load the product result (necessary before each convolution loop).
with p4_control.clear_acc select p4_acc_feedback <= 
    (others => '0')     when '1',
    p4_accumulator_reg  when others;    
    
-- Note that the accumulator is not truncated, nor is the product, for better 
-- generality.
accumulator_register:
process(clk)
begin
    if clk'event and clk='1' then
        if reset='1' then
            p4_accumulator_reg <= (others => '0');
        else
            p4_accumulator_reg <= p4_acc_feedback + p3_ext_product;
        end if;
    end if;
end process accumulator_register;


---- Data output --- straight from last pipeline stage -------------------------

-- Filter output is the whole, non-truncated accumulator value.
y <= p4_accumulator_reg(p4_accumulator_reg'high downto log2(NUM_COEFS));
y_valid <= p4_control.y_valid;


end vendor_agnostic;
