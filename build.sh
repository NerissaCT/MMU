#!/bin/bash
set -e
rm -f *.cf
rm -f waves2.vcd
ghdl -a -fsynopsys --std=08 MMU.vhd
ghdl -a -fsynopsys --std=08 MMU_TB.vhd
ghdl -e -fsynopsys --std=08 MMU_TB
ghdl -r MMU_TB --vcd=waves2.vcd  --stop-time=500ns