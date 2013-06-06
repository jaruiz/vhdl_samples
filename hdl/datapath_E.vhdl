--------------------------------------------------------------------------------
-- datapath_E.vhdl -- Floating point mini-ALU with ADD/SUB and MULT operations.
--------------------------------------------------------------------------------
-- 
-- This pipelined datapath (DP) can perform one addition and one product each
-- cycle, with a latency of 3 cycles for the product and 4 cycles for the 
-- sum. 
--
-- Put the operands in inputs data_a_in and data_b_in and raise load_a. The 
-- results will appear at the sum_out and product_out outputs after 4 and 3 
-- cycles, respectively. The parent module must select the result it needs
-- since both are provided. This DP does not support different operands for
-- ADD and MUL pipelines, though it would be easy to do.
--
-- All results are truncated; there is no rounding and there is no concept of
-- NaN or overflows (i.e. overflows may happen silently; preventing them is up 
-- to you).
--
--
-- Known bugs and problems -----------------------------------------------------
--
-- 1.- The mantissa size has been tailored to the size of the DSP48 multiplier 
-- found in the Spartan3 FPGA family and others.
-- FIXME the 18-bit size may be hardwired in some places, review.
-- This entity can be used with any FPGA family with a 18-bit unsigned 
-- multiplier, such as Altera's Cyclone-2. In FPGAs with no dedicated DSP blocks
-- this structure will be too large and too slow.
--
--------------------------------------------------------------------------------
-- FIXME: add note about 'mantissa' and 'significand'
--------------------------------------------------------------------------------
-- VHDL sample, not for actual use.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

------ Datapath package: FP data types, formats and utility functions ----------

package datapath_pkg is

-- W : word size for all integer and float data types
constant W : integer := 32;

-- M : Mantissa size, including EXPLICIT leading '1'
constant M : integer := 17; -- FIXME use smaller M for product
-- P : Mantissa scale factor
constant P : integer := 2**(M-1);
-- E : Exponent size
constant E : integer := 9;
-- EE : Exponent excess
constant EE : integer := 2**(E-1);


subtype word_t is unsigned(W-1 downto 0);
subtype mantissa_t is unsigned(M-1 downto 0);
subtype mantissa_ext_t is unsigned(M downto 0);
subtype clz_range_t is integer range 0 to M+1;
subtype exponent_t is unsigned(E-1 downto 0);
subtype exponent_ext_t is unsigned(E downto 0);

subtype sign_t is unsigned(0 downto 0);
subtype exp_diff_t is integer range 0 to M-1;

type float_t is
record
    m :                 mantissa_t;
    e :                 exponent_t;
    s :                 sign_t;
end record;


function word_to_float (d : word_t) return float_t;
function float_to_word (f : float_t) return word_t;
function count_leading_zeros(d : mantissa_ext_t) return clz_range_t;

end;

package body datapath_pkg is

function word_to_float (d : word_t) return float_t is
variable f : float_t;
begin
    f.m := d(M-1 downto 0);
    f.s := d(W-1 downto W-1);
    f.e := d(W-2 downto W-2-E+1);
    return f;
end function word_to_float;

function float_to_word (f : float_t) return word_t is
variable w : word_t;
begin
    w := f.s & f.e & resize(f.m, 22); -- FIXME magic number
    return w;
end function float_to_word;

function count_leading_zeros(d : mantissa_ext_t) return clz_range_t is
variable i, j : clz_range_t;
begin
    j := 0;
    for i in M downto 0 loop
        if d(i) = '1' then
            return j;
        end if;
        j := j + 1;
    end loop;
    return j;
end function count_leading_zeros;


end datapath_pkg;


------ Datapath entity ---------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.datapath_pkg.all;

entity datapath_E is

    generic (
        -- Data addr bus width; must be 12 <= DATA_ADDR_WIDTH <= 16
        DATA_ADDR_WIDTH : integer range 12 to 16  := 13;
        -- True to support internal 16-word deep data stack
        USE_DATA_STACK : boolean                  := true
    );

    port (
        clk :               in std_logic;
        reset :             in std_logic;

        data_a_in :         in word_t;
        data_b_in :         in word_t;

        sum_out :           out word_t;
        product_out :       out word_t;

        start :             in std_logic
    );
end datapath_E;


architecture v0_starter of datapath_E is

-- A bit of nomenclature: Each operation is performed in a number of STAGES;
-- each 'stage' is one or more combinational circuits.
-- There is a pipeline register between each two stages. Thus the signal and 
-- type names below: AP01 is the adder pipeline register between stages 0 and 1.
-- Register names are in all caps.

--**** ADDER stuff *************************************************************

signal SUM :                float_t;
signal sum_m_renorm :       mantissa_ext_t;
signal shift_amount :       clz_range_t;

type adder_stage01_reg_t is
record
    D0, D1 :                float_t;
    exp_diff :              exp_diff_t;
end record;

type adder_stage12_reg_t is
record
    D0, D1 :                float_t;
end record;

type adder_stage23_reg_t is
record
    sum_m :                 mantissa_ext_t;
    exp :                   exponent_t;
    sign :                  sign_t;
end record;

signal AP01 :               adder_stage01_reg_t;
signal AP12 :               adder_stage12_reg_t;
signal AP23 :               adder_stage23_reg_t;

--**** MULTIPLIER stuff ********************************************************

type multiplier_stage01_reg_t is
record
    D0, D1 :                float_t;
    exp_sum :               exponent_ext_t;
end record;

type multiplier_stage12_reg_t is
record
    mant_prod :             unsigned(2*M-1 downto 0);
    exp_sum :               exponent_ext_t;
    sign :                  sign_t;
end record;

signal MP01 :               multiplier_stage01_reg_t;
signal MP12 :               multiplier_stage12_reg_t;
signal MP23 :               multiplier_stage12_reg_t;
signal prod_result :        float_t;

begin

--**** MULTIPLIER **************************************************************
    
    -- NOTE: at least one latency cycle could be saved in the multiplier. But
    -- since the adder has 4 cycles of latency anyway, I have relaxed the 
    -- multiplier latency in order to improve the clock rate (e.g. in the 
    -- exponent addition).
    
    -- Note the exponent addition is actually two sums (Ea + Eb - EE), because
    -- exponents are encoded in 'excess to EE'. Those two sums have been split 
    -- across stages 1 and 2 to improve the clock rate.

    ------ Stage 0: add exponents (first of two additions) ---------------------
    multiplier_stage0:
    process(clk)
    begin
        if clk'event and clk='1' then
            if start='1' then
                MP01.exp_sum <= ('0' & data_a_in(W-2 downto W-2-E+1)) +
                                ('0' & data_b_in(W-2 downto W-2-E+1));
                MP01.D0 <= word_to_float(data_a_in);
                MP01.D1 <= word_to_float(data_b_in);
            end if;
        end if;
    end process multiplier_stage0;

    ----- Stage 1: complete exponent addition, multiply mantissas --------------
    multiplier_stage1:
    process(clk)
    begin
        if clk'event and clk='1' then
            -- remove extra EE added in previous stage
            MP12.exp_sum <= MP01.exp_sum - EE;
            MP12.mant_prod <= MP01.D0.m * MP01.D1.m;
            MP12.sign <= MP01.D0.s xor MP01.D1.s;
        end if;
    end process multiplier_stage1;

    ----- Stage 2: renormalize result ------------------------------------------
    multiplier_stage2:
    process(clk)
    begin
        if clk'event and clk='1' then
            if MP12.mant_prod(MP12.exp_sum'high) = '1' then
                MP23.exp_sum <= MP12.exp_sum + 1;
                MP23.mant_prod <= MP12.mant_prod;
            else
                MP23.exp_sum <= MP12.exp_sum;
                MP23.mant_prod <= MP12.mant_prod sll 1;
            end if;
            MP23.sign <= MP12.sign;
        end if;
    end process multiplier_stage2;

    -- Finally, truncate result and change vhdl type for output. This amounts to 
    -- renaming the MP23 register bits, there's no logic involved.
    
    -- Here's where we do the truncation (just drop least significant bits)
    prod_result.m <= MP23.mant_prod(MP23.mant_prod'high downto 
                                    MP23.mant_prod'high-M+1);
    prod_result.s <= MP23.sign;
    prod_result.e <= MP23.exp_sum(E-1 downto 0);

    product_out <= float_to_word(prod_result);


--**** ADDER *******************************************************************

    ------ stage 0: compute exponent difference & reorder operands -------------
    
    -- Operands are reordered so that always AP01.DO holds the largest mantissa 
    -- and only AP01.D1 needs shift logic for the mantissa alignment.
    -- This is just a comparator and a multiplexor.
    
    adder_stage0:
    process(clk)
    begin
        if clk'event and clk='1' then
            if start='1' then
                -- These are 2 word-wide 2x1 multiplexors
                if data_a_in(W-2 downto 0) > data_b_in(W-2 downto 0) then
                    AP01.D0      <= word_to_float(data_a_in);
                    AP01.D1      <= word_to_float(data_b_in);
                else
                    AP01.D0      <= word_to_float(data_b_in);
                    AP01.D1      <= word_to_float(data_a_in);
                end if;
            end if;
        end if;
    end process adder_stage0;

    AP01.exp_diff <= to_integer(AP01.D0.e - AP01.D1.e);

    ------ stage 1: align mantissas --------------------------------------------
    adder_stage1:
    process(clk)
    begin
        if clk'event and clk='1' then
            AP12.D1.m    <= AP01.D1.m srl AP01.exp_diff;
            AP12.D1.e    <= AP01.D0.e; -- UNUSED from this stage onwards
            AP12.D1.s    <= AP01.D1.s;
            AP12.D0      <= AP01.D0;
        end if;
    end process adder_stage1;

    ------ stage 2: add/sub aligned mantissas ----------------------------------
    adder_stage2:
    process(clk)
    begin
        if clk'event and clk='1' then
            -- note temporary mantissa sum is 1 bit wider than input mantissas
            -- and input mantissas are zero-extended before addition.
            if AP12.D0.s = AP12.D1.s then
                AP23.sum_m <= ('0' & AP12.D0.m) + ('0' & AP12.D1.m);
            else
                AP23.sum_m <= ('0' & AP12.D0.m) - ('0' & AP12.D1.m);
            end if;
            AP23.exp <= AP12.D0.e + 1;
            AP23.sign <= AP12.D0.s;
        end if;
    end process adder_stage2;

    ------ stage 3: renormalize mantissa and load result register --------------

    -- Now we shift the mantissa until the MSB is a '1'; this is a shift left
    -- of (0..18) bits and thus it needs a barrel shifter of 5 stages.
   
    -- Count leading zeros (CLZ) -- this synths as plain combinational logic.
    shift_amount <= count_leading_zeros(AP23.sum_m);

    -- Do the actual shift.
    -- The synth tools can implement this efficiently, no need to go low level.
    sum_m_renorm <= AP23.sum_m sll shift_amount;

    -- Note that the CLZ and the shift are performed in the same stage, so their
    -- delays add up. In practice this is not the speed bottleneck.

    -- Finally, register the truncated adder output 
    adder_stage3:
    process(clk)
    begin
        if clk'event and clk='1' then
            -- Here's where we do the truncation (we just drop the LSB)
            SUM.m       <= sum_m_renorm(M downto 1);
            SUM.e       <= AP23.exp - shift_amount;
            SUM.s       <= AP23.sign;
        end if;
    end process adder_stage3;

    -- Change vhdl type for output.
    -- This function call synths into just a wire fiddle, i.e. no logic.
    sum_out <= float_to_word(SUM);

end v0_starter;
