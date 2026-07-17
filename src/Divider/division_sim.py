import math
import struct

def make_lut_8bit():
    lut = []

    for i in range(128):
        val = 1.0 / (1.0 + i / 128.0)
        int_val = int(round(val * 256))
        
        if int_val > 255:
            int_val = 255
        
        lut.append(int_val)
    return lut

def hardware_model(N_mant, D_mant, N_exp, D_exp, N_sign, D_sign, lut):
    R_sign = N_sign ^ D_sign

    #NANs
    N_is_zero = (N_exp == 0)
    D_is_zero = (D_exp == 0)
    N_is_inf = (N_exp == 255)
    D_is_inf = (D_exp == 255)
    
    if (N_is_zero and D_is_zero) or (N_is_inf and D_is_inf):
        return (R_sign << 15) | 0x7FC0

    if D_is_zero and not N_is_zero:
        return (R_sign << 15) | 0x7F80
        
    if N_is_zero and not D_is_zero:
        return (R_sign << 15) | 0x0000

    R_exp = N_exp - D_exp + 127
    
    D_recip = lut[D_mant & 0x7F]
    
    Raw_mant = N_mant * D_recip

    #Align Mantissa
    Aligned_mant = Raw_mant
    
    if (Aligned_mant & 0x8000) == 0:
        Aligned_mant = Aligned_mant << 1
        R_exp = R_exp - 1
    
    #Normalize Mantissa
    sticky_bits = Aligned_mant & 0x003F
    
    if sticky_bits != 0:
        S = 1
    else:
        S = 0
        
    Aligned_mant = Aligned_mant >> 6
    Norm_mant = (Aligned_mant << 1) | S

    #Round Mantissa
    LGRS = Norm_mant & 0x0F
    Truncated_mant = Norm_mant >> 3

    if (LGRS & 0b0111 == 4):
        if (LGRS & 0x8 == 8):
            Round_mant = Truncated_mant + 1
        else:
            Round_mant = Truncated_mant
    elif (LGRS & 0b0111 > 4):
        Round_mant = Truncated_mant + 1
    else:
        Round_mant = Truncated_mant
    
    #Overflow check
    if Round_mant == 0x100:
        Round_mant = Round_mant >> 1  
        R_exp = R_exp + 1     

    #Final Result
    R_mant = Round_mant

    if R_exp >= 255:
        R_exp = 255  
    elif R_exp < 1:
        R_exp = 0

    return (R_sign << 15) | (R_exp << 7) | (R_mant & 0x7F)

def golden_model(A, B):
    
    if B == 0.0:
        if A == 0.0:
            return 0x7FC0
        else:
            if math.copysign(1, A) == math.copysign(1, B):
                return 0x7F80
            else:
                return 0xFF80
    else:
        true_quotient = A / B
    
    #Converting into fp32
    fp32_bytes = struct.pack('>f', true_quotient)    
    fp32_int = int.from_bytes(fp32_bytes, 'big')

    #Rounding
    sticky_bits = fp32_int & 0x03FFF
    
    if sticky_bits != 0:
        S = 1
    else:
        S = 0
        
    aligned = fp32_int >> 14
    norm = (aligned << 1) | S

    #Round Mantissa
    LGRS = norm & 0x0F
    truncated = norm >> 3

    if (LGRS & 0b0111 == 4):
        if (LGRS & 0x8 == 8):
            final = truncated + 1
        else:
            final = truncated
    elif (LGRS & 0b0111 > 4):
        final = truncated + 1
    else:
        final = truncated

    return final & 0xFFFF

def hex_to_float(bf16_int):
    exp = (bf16_int >> 7) & 0xFF
    frac = bf16_int & 0x7F
    if exp == 0: return 0.0
    if exp == 255: return float('inf')
    mantissa = 1.0 + (frac / 128.0)
    return (2.0 ** (exp - 127)) * mantissa

def unpack_bfloat16(bf16_int):
    sign = (bf16_int >> 15) & 1
    exp = (bf16_int >> 7) & 0xFF
    frac = bf16_int & 0x7F
    mant = (frac | 0x80) if exp > 0 else frac
    return sign, exp, mant

import time

import time

def mantissa_sweep():
    lut = make_lut_8bit()
    
    print("Starting Mantissa Sweep...")
    start_time = time.time()
    
    results = {"RNE": 0, "Faithful": 0, "Exceptions": 0, "Failed": 0}
    
    fixed_exp = 127
    fixed_sign = 0
    
    for frac_A in range(128):
        hw_A = (fixed_sign << 15) | (fixed_exp << 7) | frac_A
        
        true_A = hex_to_float(hw_A)
        N_sign, N_exp, N_mant = unpack_bfloat16(hw_A)
        
        for frac_B in range(128):
            hw_B = (fixed_sign << 15) | (fixed_exp << 7) | frac_B
            
            true_B = hex_to_float(hw_B)
            D_sign, D_exp, D_mant = unpack_bfloat16(hw_B)
            
            golden_hex = golden_model(true_A, true_B)
            hw_hex = hardware_model(N_mant, D_mant, N_exp, D_exp, N_sign, D_sign, lut)
            
            ulp_error = abs(hw_hex - golden_hex)
            
            if ulp_error == 0:
                results["RNE"] += 1
            elif ulp_error == 1:
                results["Faithful"] += 1
            elif golden_hex in [0x7FC0, 0x7F80, 0xFF80]: 
                results["Exceptions"] += 1
            else:
                results["Failed"] += 1

    elapsed = time.time() - start_time
    
    print(f"Time Elapsed: {elapsed:.4f} seconds")
    print(f"Perfect RNE: {results['RNE']:,}")
    print(f"Faithful: {results['Faithful']:,}")
    print(f"Exceptions: {results['Exceptions']:,}")
    print(f"Failed: {results['Failed']:,}")

mantissa_sweep()