load_package flow

package require cmdline
variable ::argv0 $::quartus(args)
set options {
   { "project.arg" "" "Project name" }
   { "board.arg" "" "Frequency" }
}
set usage "You need to specify options and values"
array set optshash [::cmdline::getoptions ::argv $options $usage]
set target $optshash(board)
set project_name $optshash(project)_$target
puts "Project: $project_name"
puts "Target: $target"

project_new $project_name -revision $project_name -overwrite
set_global_assignment -name TOP_LEVEL_ENTITY ${target}_top
source $project_name.tcl
project_close

