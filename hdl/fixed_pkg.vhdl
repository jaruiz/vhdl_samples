--------------------------------------------------------------------------------
-- fixed_pkg.vhdl -- Constants and functions for fixed point computation.
--------------------------------------------------------------------------------
-- 
-- NOTE: All of the functions in this package are synthesizable even with 
-- non-constant arguments, unless otherwise stated.
--
-- Known bugs and problems -----------------------------------------------------
-- 
-- 1.-  Sample size is defined as a package constant insstead of a generic. 
--      Otherwise it would be difficult to define unconstrained arrays of 
--      samples.
--      This is a problem because you can't change the constants from the 
--      command line of the synth tool like you can with a generic.
--------------------------------------------------------------------------------
-- NOTES:
--------------------------------------------------------------------------------
-- Use under the terms of LGPL license.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.txt_util.all;

package fixed_pkg is

constant SAMPLE_WIDTH : natural := 16;
constant SAMPLE_INTEGER_PART : natural := 0;

subtype sample_t is signed(SAMPLE_WIDTH-1 downto 0);

type t_coef_table is array(natural range <>) of real;

type sample_table_t is array(natural range <>) of sample_t;

-- Build coefficient table for delta[n] with the gival order.
function delta_coefs(n: natural := 8) return t_coef_table;

function real_to_sample(x: real) return sample_t;

function h_to_bram(h: t_coef_table; 
                   int_part: natural; sample_width: natural; 
                   bram_size: natural)           
         return sample_table_t;

-- Integer version of log2.
function log2(A : natural) return natural;

end;

package body fixed_pkg is


function delta_coefs(n: natural := 8) return t_coef_table is
variable h : t_coef_table(0 to n-1);
begin
    -- Xilinx ISE 9.2i does not support (others => 0.0) in this context so...
    for i in 0 to h'high loop
        h(i) := 0.0;
    end loop;
    h(0) := 0.999999999;
    return h;
end function delta_coefs;

function h_to_bram(h: t_coef_table; 
                   int_part: natural; sample_width: natural; 
                   bram_size: natural) return sample_table_t is
variable k : sample_table_t(0 to bram_size-1);
begin
    for i in 0 to h'high loop
        --k(i) := to_signed(i+16, SAMPLE_WIDTH);--real_to_sample(h(i));
        k(i) := real_to_sample(h(i));
    end loop;
    for i in h'high+1 to bram_size-1 loop
        k(i) := (others => '0');
    end loop;
    
    return k;
end function h_to_bram;


function real_to_sample(x: real) return sample_t is
variable xe : real;
variable xf : signed(31 downto 0);
variable sign_ext : signed(31 downto 0);
begin
    xe := x * real(2**(SAMPLE_WIDTH - SAMPLE_INTEGER_PART -1));
    xf := to_signed(integer(floor(xe)), 32);
    
    -- Make sure the number fits the format
    sign_ext := (others => xf(SAMPLE_WIDTH-1));
    --assert xf(31 downto SAMPLE_WIDTH) = sign_ext(31 downto SAMPLE_WIDTH)
    --report "Sample can't be quantized with "& str(SAMPLE_INTEGER_PART)&
    --       " integer width."
    --severity failure;
    
    -- FIXME should make sure the quentization error is below some threshold
  
    return xf(SAMPLE_WIDTH-1 downto 0);
end function real_to_sample;

function log2(A : natural) return natural is
begin
    for I in 1 to 30 loop -- Works for up to 32 bit integers
        if(2**I >= A) then 
            return(I);
        end if;
    end loop;
    return(30);
end function log2;

end fixed_pkg;
