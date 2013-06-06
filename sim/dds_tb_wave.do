onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -format Logic /dds_tb/clk
add wave -noupdate -format Logic /dds_tb/sample_valid
add wave -noupdate -group {Sync outputs}
add wave -noupdate -group {Sync outputs} -format Logic /dds_tb/sync(3)
add wave -noupdate -group {Sync outputs} -format Logic /dds_tb/sync(2)
add wave -noupdate -group {Sync outputs} -format Logic /dds_tb/sync(1)
add wave -noupdate -group {Sync outputs} -format Logic /dds_tb/sync(0)
add wave -noupdate -expand -group Internal
add wave -noupdate -group Internal -format Logic /dds_tb/inst_dds/update_acc
add wave -noupdate -group Internal -format Logic /dds_tb/inst_dds/update_sine
add wave -noupdate -group Internal -format Logic /dds_tb/inst_dds/update_cosine
add wave -noupdate -color Khaki -format Analog-Step -height 100 -radix decimal -scale 0.029999999999999999 /dds_tb/sample_sin
add wave -noupdate -color Goldenrod -format Analog-Step -offset 520.0 -radix decimal -scale 0.029999999999999999 /dds_tb/sample_cos
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {367450000 ps} 0}
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
WaveRestoreZoom {0 ps} {2100105 ns}
