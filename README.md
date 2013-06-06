VHDL code samples
=================

This repository contains VHDL code samples meant to be shown to potential 
employers; they are not fit for any generally useful purpose.

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

The ALU is meant to be parametrizable in some subsequent revision but it 
currently is not -- the parametrization generics are not used consistently and
it has not been tested with values other than default. The parameters determine
the size of the operands (mantissa and exponent) and are tailored to the DSP
block of Spartan chips. 


All the test benches have been tried only with Modelsim SE 6.3.


The FIR test bench is the only one resembling a real test bench. It will run 
a test signal through the FIR, logging the output to a text file formatted as 
a matlab script. The results can then ve validated by running script 
/sim/fir_test.m

The test bench for the DDS module is meant only for visual display. It will 
run the DDS with two different frequencies and will do no verification on
the DDS output, it will only display it in the simulation wave window.

The test bench for the ALU is also for display only, though some token effort 
is done to validate the results: the error for each operation is computed and 
a warning is raised if it exceeds some arbitrary threshold.
