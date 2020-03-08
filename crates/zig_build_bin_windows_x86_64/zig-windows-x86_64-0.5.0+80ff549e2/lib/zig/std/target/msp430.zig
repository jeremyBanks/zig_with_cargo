const std = @import("../std.zig");
const CpuFeature = std.Target.Cpu.Feature;
const CpuModel = std.Target.Cpu.Model;

pub const Feature = enum {
    ext,
    hwmult16,
    hwmult32,
    hwmultf5,
};

pub usingnamespace CpuFeature.feature_set_fns(Feature);

pub const all_features = blk: {
    const len = @typeInfo(Feature).Enum.fields.len;
    std.debug.assert(len <= CpuFeature.Set.needed_bit_count);
    var result: [len]CpuFeature = undefined;
    result[@enumToInt(Feature.ext)] = .{
        .llvm_name = "ext",
        .description = "Enable MSP430-X extensions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.hwmult16)] = .{
        .llvm_name = "hwmult16",
        .description = "Enable 16-bit hardware multiplier",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.hwmult32)] = .{
        .llvm_name = "hwmult32",
        .description = "Enable 32-bit hardware multiplier",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.hwmultf5)] = .{
        .llvm_name = "hwmultf5",
        .description = "Enable F5 series hardware multiplier",
        .dependencies = featureSet(&[_]Feature{}),
    };
    const ti = @typeInfo(Feature);
    for (result) |*elem, i| {
        elem.index = i;
        elem.name = ti.Enum.fields[i].name;
    }
    break :blk result;
};

pub const cpu = struct {
    pub const generic = CpuModel{
        .name = "generic",
        .llvm_name = "generic",
        .features = featureSet(&[_]Feature{}),
    };
    pub const msp430 = CpuModel{
        .name = "msp430",
        .llvm_name = "msp430",
        .features = featureSet(&[_]Feature{}),
    };
    pub const msp430x = CpuModel{
        .name = "msp430x",
        .llvm_name = "msp430x",
        .features = featureSet(&[_]Feature{
            .ext,
        }),
    };
};

/// All msp430 CPUs, sorted alphabetically by name.
/// TODO: Replace this with usage of `std.meta.declList`. It does work, but stage1
/// compiler has inefficient memory and CPU usage, affecting build times.
pub const all_cpus = &[_]*const CpuModel{
    &cpu.generic,
    &cpu.msp430,
    &cpu.msp430x,
};
