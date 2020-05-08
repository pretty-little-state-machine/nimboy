#!/bin/bash
echo "RUNNING BLARRG'S TEST ROMS!"
ls roms/gb-test-roms/cpu_instrs/individual | while read line
do 
  ./main --rom="roms/gb-test-roms/cpu_instrs/individual/${line}"
done