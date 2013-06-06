onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider Internal
add wave -noupdate -format Logic /fir_tb/clk
add wave -noupdate -color {Cornflower Blue} -format Literal -radix hexadecimal /fir_tb/x
add wave -noupdate -color {Cadet Blue} -format Logic /fir_tb/x_valid
add wave -noupdate -color Wheat -format Literal -radix hexadecimal /fir_tb/y
add wave -noupdate -color Khaki -format Logic /fir_tb/y_valid
add wave -noupdate -format Literal /fir_tb/yr
add wave -noupdate -divider Internal
add wave -noupdate -color Pink -format Literal -radix hexadecimal /fir_tb/uut/p0_i_reg
add wave -noupdate -color White -format Literal -radix hexadecimal /fir_tb/uut/p0_n_reg
add wave -noupdate -divider {Pipeline Stages}
add wave -noupdate -format Logic /fir_tb/uut/p0_idle
add wave -noupdate -color {Steel Blue} -format Literal -radix hexadecimal /fir_tb/uut/p2_xz_reg
add wave -noupdate -color {Indian Red} -format Literal -radix hexadecimal /fir_tb/uut/p2_h_reg
add wave -noupdate -color {Olive Drab} -format Literal -radix hexadecimal /fir_tb/uut/p3_product_reg
add wave -noupdate -format Logic /fir_tb/uut/p4_control.clear_acc
add wave -noupdate -color Tan -format Literal -radix hexadecimal /fir_tb/uut/p4_accumulator_reg
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {40700000 ps} 0}
configure wave -namecolwidth 150
configure wave -valuecolwidth 62
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
update
WaveRestoreZoom {39526933 ps} {42135309 ps}
