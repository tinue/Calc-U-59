// ObjC++-only conversions shared by the Bridge/ wrappers. Never import from
// the Swift bridging header.
#import <Foundation/Foundation.h>
#import "TITypes.h"
#include "../Core/TraceTypes.hpp"
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

inline NSString* ns(const std::string& s) {
    return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}
inline std::string cpp(NSString* s) { return s ? std::string(s.UTF8String) : std::string(); }
inline NSData* nsData(const std::vector<uint8_t>& v) { return [NSData dataWithBytes:v.data() length:v.size()]; }
inline std::vector<uint8_t> bytes(NSData* d) {
    const auto* p = static_cast<const uint8_t*>(d.bytes);
    return std::vector<uint8_t>(p, p + d.length);
}

// TICpuFrame mirrors CpuFrame field for field, so a frame converts with one copy.
static_assert(sizeof(TICpuFrame) == sizeof(CpuFrame), "TICpuFrame must mirror CpuFrame");
#define SAME_OFFSET(f) static_assert(offsetof(TICpuFrame, f) == offsetof(CpuFrame, f), "TICpuFrame." #f)
SAME_OFFSET(seqno); SAME_OFFSET(pc); SAME_OFFSET(opcode); SAME_OFFSET(digit); SAME_OFFSET(postDigit);
SAME_OFFSET(cycleWeight); SAME_OFFSET(KR); SAME_OFFSET(SR); SAME_OFFSET(fA); SAME_OFFSET(fB);
SAME_OFFSET(cpuFlags); SAME_OFFSET(R5); SAME_OFFSET(A); SAME_OFFSET(B); SAME_OFFSET(C); SAME_OFFSET(D);
SAME_OFFSET(E); SAME_OFFSET(SCOM); SAME_OFFSET(Sout); SAME_OFFSET(EXT); SAME_OFFSET(PREG); SAME_OFFSET(flags);
SAME_OFFSET(m_libAddr); SAME_OFFSET(REG_ADDR); SAME_OFFSET(RAM_ADDR); SAME_OFFSET(RAM_OP);
SAME_OFFSET(m_libAddrReadPos); SAME_OFFSET(displayOn); SAME_OFFSET(maxDigitDecay);
#undef SAME_OFFSET

inline TICpuFrame tiCpuFrame(const CpuFrame& f) {
    TICpuFrame t;
    std::memcpy(&t, &f, sizeof t);
    return t;
}
