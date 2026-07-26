@tool
extends EditorPlugin

# LogPop is registered via class_name + @icon on scripts/log_pop.gd.
# This EditorPlugin must remain so enabling the addon exposes that class
# in the Create New Node / Add Child Node dialog (scripts under addons/ are gated).
