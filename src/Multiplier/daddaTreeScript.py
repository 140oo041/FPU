
def daddaTree():
    partialProducts = [[] for _ in range(16)]
    rtl = []
    daddaNumbers = [6, 4, 3, 2]

    rtl.append("module dadda_multiplier(")
    rtl.append("\tinput wire[7:0] a, b,")
    rtl.append("\toutput wire[15:0] factor1, factor2")
    rtl.append("\t);\n")

    for i in range(8):
        for j in range(8):
            wireName = f"pp_{i}_{j}"
            ppWeight = i + j

            partialProducts[ppWeight].append(wireName)

            rtl.append(f"\twire {wireName};")
            rtl.append(f"\tassign {wireName} = a[{i}] & b[{j}];")
            rtl.append(f"\n")

    for stage in daddaNumbers:
        updatedPartials = [[] for _ in range(16)]

        for colNum, col in enumerate(partialProducts):

            incomingCarries = len(updatedPartials[colNum])

            totalDots = len(col) + incomingCarries

            if totalDots > stage:
                reductionAmount = totalDots - stage
                internalIndex = 0
                faCount = 0
                haCount = 0

                while reductionAmount > 0:
                    if reductionAmount == 1:
                        sum_wire = f"s{stage}_c{colNum}_ha{haCount}_sum"
                        carry_wire = f"s{stage}_c{colNum}_ha{haCount}_carry"
                        rtl.append(f"\twire {sum_wire}, {carry_wire};")
                        rtl.append(f"\thalfAdder HA_{stage}_{colNum}_{haCount}({col[internalIndex]}, {col[internalIndex + 1]}, {sum_wire}, {carry_wire});\n")

                        updatedPartials[colNum].append(sum_wire)
                        updatedPartials[colNum + 1].append(carry_wire)

                        internalIndex += 2
                        reductionAmount -= 1
                        haCount += 1

                    elif reductionAmount >= 2:
                        sum_wire = f"s{stage}_c{colNum}_fa{faCount}_sum"
                        carry_wire = f"s{stage}_c{colNum}_fa{faCount}_carry"
                        rtl.append(f"\twire {sum_wire}, {carry_wire};")
                        rtl.append(f"\tfullAdder FA_{stage}_{colNum}_{faCount}({col[internalIndex]}, {col[internalIndex + 1]}, {col[internalIndex + 2]}, {sum_wire}, {carry_wire});\n")

                        updatedPartials[colNum].append(sum_wire)
                        updatedPartials[colNum + 1].append(carry_wire)

                        internalIndex += 3
                        reductionAmount -= 2
                        faCount += 1

                while internalIndex < len(col):
                    updatedPartials[colNum].append(col[internalIndex])
                    internalIndex += 1

            else:
                for wire in col:
                    updatedPartials[colNum].append(wire)

        partialProducts = updatedPartials

    for colNum in range(16):
        bucket = partialProducts[colNum]

        if len(bucket) > 0:
            rtl.append(f"\tassign factor1[{colNum}] = {bucket[0]};")
        else:
            rtl.append(f"\tassign factor1[{colNum}] = 1'b0;")

        if len(bucket) > 1:
            rtl.append(f"\tassign factor2[{colNum}] = {bucket[1]};")
        else:
            rtl.append(f"\tassign factor2[{colNum}] = 1'b0;")

    rtl.append(f"endmodule")

    for line in rtl:
        print(line)

daddaTree()