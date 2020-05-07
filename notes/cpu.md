# Central Processing Unit Notes
 ## 16 bit and 8 bit signed
This note on 16 bit wiht 8 bit signed mathi is taken from [Stack Exchange](https://stackoverflow.com/questions/5159603/gbz80-how-does-ld-hl-spe-affect-h-and-c-flags)
For both 16bit SP + s8 (signed immediate) operations:

the carry flag is set if there's an overflow from the 7th to 8th bit.

the half carry flag is set if there's an overflow from the 3rd into the 4th bit.

    local D8 = self:Read(self.PC+1)
    local S8 = ((D8&127)-(D8&128))
    local SP = self.SP + S8 

    if S8 >= 0 then
        self.Cf = ( (self.SP & 0xFF) + ( S8 ) ) > 0xFF
        self.Hf = ( (self.SP & 0xF) + ( S8 & 0xF ) ) > 0xF
    else
        self.Cf = (SP & 0xFF) <= (self.SP & 0xFF)
        self.Hf = (SP & 0xF) <= (self.SP & 0xF)
    end

## DAA Instruction
This note was pulled from the Z-80 BCD discussion [WTF is the DAA instruction?](https://ehaskins.com/2018-01-30%20Z80%20DAA/)

Turns out there’s a lot of poorly documented edge cases in daa. This is the code I ended up with, which works.

    function DAA(value: number, subtraction: bool, carry: bool, halfCarry: bool){
    let correction = 0;

    let setFlagC = 0;
    if (flagH || (!flagN && (value & 0xf) > 9)) {
        correction |= 0x6;
    }

    if (flagC || (!flagN && value > 0x99)) {
        correction |= 0x60;
        setFlagC = FLAG_C;
    }

    value += flagN ? -correction : correction;

    value &= 0xff;

    const setFlagZ = value === 0 ? FLAG_Z : 0;

    regF &= ~(FLAG_H | FLAG_Z | FLAG_C);
    regF |= setFlagC | setFlagZ;

    return { value, carry, zero };