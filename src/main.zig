const std = @import("std");
const testing = std.testing;

const riffChunkId: [4]u8 = [_]u8{ 'R', 'I', 'F', 'F' };
const riffFormat: [4]u8 = [_]u8{ 'W', 'A', 'V', 'E' };
const fmtChunkId: [4]u8 = [_]u8{ 0x66, 0x6d, 0x74, 0x20 };
const fmtSubChunkSize: [4]u8 = [_]u8{ 0x10, 0x00, 0x00, 0x00 };
const fmtAudioFormat: [2]u8 = [_]u8{ 0x01, 0x00 };
const dataChunkId: [4]u8 = [_]u8{ 0x64, 0x61, 0x74, 0x61 };

pub fn WavParser(
    comptime numChannels: usize,
    comptime itype: type,
    comptime otype: type,
) type {
    return struct {
        dataSize: usize,
        sampleRate: usize,
        byteRate: usize,
        blockAlign: usize,

        const Self = @This();

        pub fn parseAudio(
            self: Self,
            comptime ibufferSize: usize,
            comptime obufferSize: usize,
            ibuffer: *const [ibufferSize]u8,
            obuffer: *[numChannels][obufferSize]otype,
        ) void {
            _ = self;
            const ioratio: usize = ibufferSize / obufferSize;
            comptime std.debug.assert((ibufferSize / obufferSize) == (@bitSizeOf(itype) / 8));
            @setEvalBranchQuota(3 * numChannels * obufferSize);
            inline for (0..numChannels) |ch| {
                inline for (0..obufferSize) |idx| {
                    const s = numChannels * ioratio * idx + ioratio * ch;
                    const h = comptime ioratio;
                    const ovalue: itype = std.mem.readIntNative(itype, ibuffer[s .. s + h]);
                    obuffer[ch][idx] = @intToFloat(otype, ovalue) / @intToFloat(otype, std.math.maxInt(itype));
                }
            }
        }

        pub fn parseHeader(header: [44]u8) !Self {
            // validate fixed headers
            try parseFixedHeader(4, riffChunkId, header[0..4]);
            try parseFixedHeader(4, riffFormat, header[8..12]);
            try parseFixedHeader(4, fmtChunkId, header[12..16]);
            try parseFixedHeader(4, fmtSubChunkSize, header[16..20]);
            try parseFixedHeader(2, fmtAudioFormat, header[20..22]);
            try parseFixedHeader(4, dataChunkId, header[36..40]);

            // validate number of params as specified
            if (numChannels != parseUnsignedBe(2, header[22..24])) {
                return error.InvalidParam;
            }

            // validate number of params as specified
            if (@bitSizeOf(itype) != parseUnsignedBe(2, header[34..36])) {
                return error.InvalidParam;
            }

            return Self{
                .sampleRate = parseUnsignedBe(4, header[24..28]),
                .byteRate = parseUnsignedBe(4, header[28..32]),
                .blockAlign = parseUnsignedBe(2, header[32..34]),
                .dataSize = parseUnsignedBe(4, header[40..44]),
            };
        }

        fn parseFixedHeader(comptime size: usize, comptime header: [size]u8, data: *const [size]u8) !void {
            for (header, data) |headerByte, dataByte| {
                if (dataByte != headerByte) {
                    return error.InvalidParam;
                }
            }
        }

        fn parseUnsignedBe(comptime size: usize, data: *const [size]u8) usize {
            var num: usize = 0;
            inline for (0..size) |idx| {
                num += @shlExact(@as(usize, data[idx]), 8 * (idx));
            }

            return num;
        }
    };
}

test "read a wav file" {
    var file = try std.fs.cwd().openFile("billie.wav", .{});
    defer file.close();

    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(1, i16, f32).parseHeader(headerData);
    std.debug.print("\n{any}\n{any}\n{any}\n{any}\n", header);

    // next data
    var idata: [1024]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [1][512]f32 = [_][512]f32{[_]f32{0.0} ** 512};
    header.parseAudio(1024, 512, &idata, &odata);
    for (0..512) |idx| {
        std.debug.print("{any} :: {any}\n", .{ @intToFloat(f32, idx) / @intToFloat(f32, header.sampleRate), odata[0][idx] });
    }
}
