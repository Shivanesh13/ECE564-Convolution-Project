#!/bin/bash

python3 img2svmem.py ../images/debug_32x32.png \
	-o ../inputs/debug0.dat \
	--kernel box 

python3 img2svmem.py ../images/debug_32x32.png \
	-o ../inputs/debug1.dat \
	--kernel edge

python3 img2svmem.py ../images/test_32x32_grad8.png \
	-o ../inputs/debug2.dat \
	--kernel box 

python3 img2svmem.py ../images/test_32x32_grad8.png \
	-o ../inputs/debug3.dat \
	--kernel edge

python3 img2svmem.py ../images/input0.jpg \
        -o  ../inputs/input0.dat \
        --kernel box 

python3 img2svmem.py ../images/input0.jpg \
        -o  ../inputs/input1.dat \
        --kernel edge

python3 img2svmem.py ../images/input1.tiff \
        -o  ../inputs/input2.dat \
        --kernel box

python3 img2svmem.py ../images/input1.tiff \
        -o  ../inputs/input3.dat \
        --kernel edge

python3 img2svmem.py ../images/input2.png \
        -o  ../inputs/input4.dat \
        --kernel box

python3 img2svmem.py ../images/input2.png \
        -o  ../inputs/input5.dat \
        --kernel edge


python3 ./conv.py \
  ../inputs/debug0.dat \
  -o ../outputs/debug0.464.png \
  --out-mem ../outputs/debug0.464.dat \
  --dims "32x32" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/debug1.dat \
  -o ../outputs/debug1.464.png \
  --out-mem ../outputs/debug1.464.dat \
  --dims "32x32" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/debug2.dat \
  -o ../outputs/debug2.464.png \
  --out-mem ../outputs/debug2.464.dat \
  --dims "32x32" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/debug3.dat \
  -o ../outputs/debug3.464.png \
  --out-mem ../outputs/debug3.464.dat \
  --dims "32x32" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/debug0.dat \
  -o ../outputs/debug0.564.png \
  --out-mem ../outputs/debug0.564.dat \
  --dims "32x32" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/debug1.dat \
  -o ../outputs/debug1.564.png \
  --out-mem ../outputs/debug1.564.dat \
  --dims "32x32" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/debug2.dat \
  -o ../outputs/debug2.564.png \
  --out-mem ../outputs/debug2.564.dat \
  --dims "32x32" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/debug3.dat \
  -o ../outputs/debug3.564.png \
  --out-mem ../outputs/debug3.564.dat \
  --dims "32x32" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00


python3 ./conv.py \
  ../inputs/input0.dat \
  -o ../outputs/output0.464.png \
  --out-mem ../outputs/output0.464.dat \
  --dims "1024x1024" \
  --offset 0x10 \
  --kernel 0x00
  
python3 ./conv.py \
  ../inputs/input1.dat \
  -o ../outputs/output1.464.png \
  --out-mem ../outputs/output1.464.dat \
  --dims "1024x1024" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input2.dat \
  -o ../outputs/output2.464.png \
  --out-mem ../outputs/output2.464.dat \
  --dims "1024x1024" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input3.dat \
  -o ../outputs/output3.464.png \
  --out-mem ../outputs/output3.464.dat \
  --dims "1024x1024" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input4.dat \
  -o ../outputs/output4.464.png \
  --out-mem ../outputs/output4.464.dat \
  --dims "1024x1024" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input5.dat \
  -o ../outputs/output5.464.png \
  --out-mem ../outputs/output5.464.dat \
  --dims "1024x1024" \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input0.dat \
  -o ../outputs/output0.564.png \
  --out-mem ../outputs/output0.564.dat \
  --dims "1024x1024" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input1.dat \
  -o ../outputs/output1.564.png \
  --out-mem ../outputs/output1.564.dat \
  --dims "1024x1024" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input2.dat \
  -o ../outputs/output2.564.png \
  --out-mem ../outputs/output2.564.dat \
  --dims "1024x1024" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input3.dat \
  -o ../outputs/output3.564.png \
  --out-mem ../outputs/output3.564.dat \
  --dims "1024x1024" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --emit \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input4.dat \
  -o ../outputs/output4.564.png \
  --out-mem ../outputs/output4.564.dat \
  --dims "1024x1024" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

python3 ./conv.py \
  ../inputs/input5.dat \
  -o ../outputs/output5.564.png \
  --out-mem ../outputs/output5.564.dat \
  --dims "1024x1024" \
  --act lrelu \
  --pool avg \
  --padding 1 \
  --offset 0x10 \
  --kernel 0x00

