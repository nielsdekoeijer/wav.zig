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
            const hop: usize = @bitSizeOf(itype) / 8;
            comptime std.debug.assert(@mod(ibufferSize, hop) == 0);
            comptime std.debug.assert(((ibufferSize / numChannels) / hop) == obufferSize);
            @setEvalBranchQuota(3 * numChannels * obufferSize);
            inline for (0..numChannels) |ch| {
                inline for (0..obufferSize) |idx| {
                    const s: usize = numChannels * hop * idx + hop * ch;
                    const h: usize = comptime hop;
                    switch (itype) {
                        i16, i24, i32 => {
                            const ovalue: itype = std.mem.readIntNative(itype, ibuffer[s .. s + h]);
                            obuffer[ch][idx] = @intToFloat(otype, ovalue) /
                                @intToFloat(otype, std.math.maxInt(itype));
                        },
                        u8 => {
                            const ovalue: itype = std.mem.readIntNative(itype, ibuffer[s .. s + h]);
                            obuffer[ch][idx] = (@intToFloat(otype, ovalue) -
                                @intToFloat(otype, std.math.maxInt(i8))) /
                                @intToFloat(otype, std.math.maxInt(i8));
                        },
                        else => unreachable,
                    }
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

test "1ch_s16" {
    var file = try std.fs.cwd().openFile("./data/sin_1ch_s16_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = i16;
    const otype = f32;
    const nchan = 1;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 2 * 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}

test "1ch_s24" {
    var file = try std.fs.cwd().openFile("./data/sin_1ch_s24_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = i24;
    const otype = f32;
    const nchan = 1;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 3 * 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}

test "1ch_s32" {
    var file = try std.fs.cwd().openFile("./data/sin_1ch_s32_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = i32;
    const otype = f32;
    const nchan = 1;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 4 * 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}

test "1ch_u8" {
    var file = try std.fs.cwd().openFile("./data/sin_1ch_u8_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = u8;
    const otype = f32;
    const nchan = 1;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}

test "2ch_s16" {
    var file = try std.fs.cwd().openFile("./data/sin_2ch_s16_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = i16;
    const otype = f32;
    const nchan = 2;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 2 * 2 * 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}

test "2ch_s24" {
    var file = try std.fs.cwd().openFile("./data/sin_2ch_s24_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = i24;
    const otype = f32;
    const nchan = 2;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 2 * 3 * 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}

test "2ch_s32" {
    var file = try std.fs.cwd().openFile("./data/sin_2ch_s32_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = i32;
    const otype = f32;
    const nchan = 2;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 2 * 4 * 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}

test "2ch_u8" {
    var file = try std.fs.cwd().openFile("./data/sin_2ch_u8_pcm.wav", .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var stream = reader.reader();

    const itype = u8;
    const otype = f32;
    const nchan = 2;

    // first read header
    var headerData: [44]u8 = undefined;
    _ = try stream.read(&headerData);
    const header = try WavParser(nchan, itype, otype).parseHeader(headerData);

    // next data
    const in = 2 * 10;
    const on = 10;

    var idata: [in]u8 = undefined;
    _ = try stream.read(&idata);
    var odata: [nchan][on]otype = [_][on]otype{[_]otype{0.0} ** on} ** nchan;
    header.parseAudio(in, on, &idata, &odata);
    for (0..nchan) |ch| {
        for (0..on) |idx| {
            std.debug.print("{any}\n", .{odata[ch][idx]});
        }
    }
}
