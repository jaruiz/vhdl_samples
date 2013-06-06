onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -format Logic /datapath_e_tb/clk
add wave -noupdate -color Goldenrod -format Logic /datapath_e_tb/start
add wave -noupdate -color {Sea Green} -format Literal /datapath_e_tb/a
add wave -noupdate -color {Olive Drab} -format Literal /datapath_e_tb/b
add wave -noupdate -color Khaki -format Literal /datapath_e_tb/sum
add wave -noupdate -color {Cadet Blue} -format Literal /datapath_e_tb/product
add wave -noupdate -divider Internal
add wave -noupdate -format Literal -radix hexadecimal /datapath_e_tb/data_a
add wave -noupdate -format Literal -radix hexadecimal /datapath_e_tb/data_b
add wave -noupdate -format Literal -radix unsigned /datapath_e_tb/uut/mp01
add wave -noupdate -format Literal -radix unsigned /datapath_e_tb/uut/mp12
add wave -noupdate -format Literal -radix unsigned /datapath_e_tb/uut/mp23
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {15000 ps} 0} {{Cursor 2} {45000 ps} 0}
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
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
WaveRestoreZoom {0 ps} {1522500 ps}
