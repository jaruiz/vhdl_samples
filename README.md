VHDL code samples
=================

This repository contains VHDL code samples meant to be shown to potential 
employers; unless you are one, the contents of this repository are unlikely 
to interest you.


These samples are a complement to the open-hardware projects mentioned in 
my resume. They are not very remarkable but at least they do show that I can 
turn an algorithm description into decent logic, or so I think.


The source for each module includes some implementation and usage details that 
I will not repeat in this readme file.


Modules
-------

The code samples include three small DSP modules plus a simple test bench for 
each of them:

1. A parametrizable fixed point DDS.
2. A fixed point FIR filter.
3. A tiny floating point ALU (add and multiply only, not parametrizable).


The DDS can be parametrized through the use of VHDL generics. The structure of 
the DDS includes constant tables (the DDS uses linear interpolation, see the 
source) which are automatically computed from the generics in synthesis time.


The FIR cannot be parametrized at all, other than supplying the order and the
coefficient table as generics. The coefficients are supplied as real values 
which are converted to a fixed point number table in synthesis time.

The FIR has been designed to use a single RAM block for both delay queue and
coefficient table, using the dual port RAM capability of most FPGA architectures. 
This is done using a vendor-independent VHDL idiom that works at least with 
recent versions of Xilinx and Altera tools.



The ALU was meant to be parametrizable in some subsequent revision but it 
currently is not -- the parametrization generics are not used consistently and
it has not been tested with values other than default. The parameters determine
the size of the operands (mantissa and exponent) and are tailored to the DSP
block of Spartan chips, though the module can be synthesized for Altera chips
too.

The sources are all in directory /hdl.

No synthesis tool other than the free ones supplied by Xilinx and Altera has 
been used with these modules; they may contain constructs incompatible with
other tools.


Simulation Scripts
-------------------

Directory /sim includes one Modelsim simulation script for each of the three 
samples. There is a second script for each sample, named '*_wave.do', used to 
configure the wave window and invoked from the main simulation script.



Test Benches
------------


All the test benches have been tried only with Modelsim SE 6.3.


The FIR test bench is the only one resembling a real test bench. It will run 
a test signal through the FIR, logging the output to a text file formatted as 
a matlab script. The results can then be validated by running script 
/sim/fir_test.m. 
This script will display the actual and expected signal sequences, and compute
the relative error.


The test bench for the DDS module is meant only for visual display. It will 
run the DDS with two different frequencies and will do no verification on
the DDS output, it will only display it in the simulation wave window.
It wouldn't be difficult extending this test bench so that waveform outputs were
logged to file so that they could be verified with Matlab/Octave/SciPy scripts.


The test bench for the ALU is also for display only, though some token effort 
is done to validate the results: the error for each operation is computed and 
a warning is raised if it exceeds some arbitrary threshold.



Synthesis results
-----------------


These are some synthesis results for area and speed (no constraints).


<table>
    <tr>
        <td colspan='5'>
        Spartan-3 speed grade -4 (ISE 14 set for speed, synthesis only)
        </td>
    <tr>
        <td>datapath_E (17-bit mantissa, 9-bit exponent)</td>
        <td>352 LUTs</td>
        <td>1 MULT18x18</td>
        <td></td>
        <td>125 MHz</td>
    </tr>
    <tr>
        <td>dds</td>
        <td>130 LUTs</td>
        <td>1 MULT18x18</td>
        <td></td>
        <td>66 MHz</td>
    </tr>
    <tr>
        <td>fir (16-bit samples, 128 coefs)</td>
        <td>208 LUTs</td>
        <td>4 MULT18x18</td>
        <td>1 BRAM</td>
        <td>90 MHz</td>
    </tr>
</table>


<table>
    <tr>
        <td colspan='5'>
        Cyclone-2 -7 (Quartus-2 11 set for balance, full compilation)
        </td>
    <tr>
        <td>datapath_E (17-bit mantissa, 9-bit exponent)</td>
        <td>402 LEs</td>
        <td>2 MULT9x9</td>
        <td></td>
        <td>~125 MHz</td>
    </tr>
    <tr>
        <td>dds</td>
        <td>123 LEs</td>
        <td>2 MULT9x9</td>
        <td></td>
        <td>~90 MHz</td>
    </tr>
    <tr>
        <td>fir (16-bit samples, 128 coefs)</td>
        <td>111 LEs</td>
        <td>2 MULT9x9</td>
        <td>1 M4K RAM block</td>
        <td>~130 MHz</td>
    </tr>
</table>

The synthesis has been performed with default values for all generics.


