#!/bin/bash
# echo "RUNNING BLARRG'S CPU INSTRUCTION EXECUTION TEST ROMS!"
# ./main --rom="roms/gb-test-roms/cpu_instrs/cpu_instrs.gb"
# if [ $? -ne 0 ]
# then
  ls roms/gb-test-roms/cpu_instrs/individual | while read line
  do 
    ./main --rom="roms/gb-test-roms/cpu_instrs/individual/${line}"
  done
# fi
echo
echo "RUNNING BLARRG'S CPU INSTRUCTION TIMING TEST ROMS!"
./main --rom="roms/gb-test-roms/instr_timing/instr_timing.gb"
echo
echo "RUNNING BLARRG'S MEMORY TIMING TEST ROMS!"
./main --rom="roms/gb-test-roms/mem_timing/mem_timing.gb"
if [ $? -ne 0 ]
then
  ls roms/gb-test-roms/mem_timing/individual | while read line
  do 
    ./main --rom="roms/gb-test-roms/mem_timing/individual/${line}"
  done
fi
echo
