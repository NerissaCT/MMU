#!/bin/bash
rm -f *.cf
rm -f waves2.vcd
ghdl -a MMU.vhd
ghdl -a MMU_TB.vhd
ghdl -e MMU_TB
ghdl -r MMU_TB --vcd=waves2.vcd  --stop-time=150ns