#!/bin/bash
set -e
ghdl -a MMU.vhd
ghdl -a MMUTB.vhd
ghdl -r MMUTB --vcd=waves.vcd   --stop-time=150ns
gtkwave waves.vcd
