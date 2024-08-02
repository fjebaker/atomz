const std = @import("std");

const INDENT_SIZE = 2;
const StringMap = std.StringHashMap([]const u8);

pub const Element = struct {
    attributes: ?StringMap = null,
    text: ?[]const u8 = null,

    pub fn put(self: *Element, name: []const u8, value: []const u8) !void {
        try self.attributes.?.put(name, value);
    }
};

fn writeIndent(writer: anytype, n: usize) !void {
    try writer.writeByteNTimes(' ', n * INDENT_SIZE);
}

pub const NamedElement = struct {
    name: []const u8,
    element: Element,

    pub fn write(self: *const NamedElement, writer: anytype) !void {
        try writer.print("<{s}", .{self.name});
        // do the attributes for that item
        if (self.element.attributes) |attr| {
            var itt = attr.iterator();
            while (itt.next()) |i| {
                try writer.print(
                    " {s}=\"{s}\"",
                    .{ i.key_ptr.*, i.value_ptr.* },
                );
            }
        }

        if (self.element.text) |text| {
            try writer.print(
                ">{s}</{s}>",
                .{ text, self.name },
            );
        } else {
            try writer.writeAll("/>");
        }
    }
};

const ElementList = std.ArrayList(NamedElement);

pub const ElementCollection = struct {
    list: ElementList,
    pub fn add(self: *ElementCollection, name: []const u8, el: Element) !void {
        try self.list.append(.{ .name = name, .element = el });
    }

    inline fn setNamed(
        self: *ElementCollection,
        comptime replace: bool,
        field: []const u8,
        el: Element,
    ) !void {
        for (self.list.items, 0..) |item, i| {
            if (std.mem.eql(u8, item.name, field)) {
                _ = self.list.swapRemove(i);
                try self.list.insert(i, .{ .name = field, .element = el });
                return;
            }
        }
        if (replace) {
            return error.UnknownElement;
        } else {
            try self.list.append(.{ .name = field, .element = el });
        }
    }

    pub fn set(self: *ElementCollection, name: []const u8, el: Element) !void {
        try self.setNamed(true, name, el);
    }

    pub fn addOrSet(self: *ElementCollection, name: []const u8, el: Element) !void {
        try self.setNamed(false, name, el);
    }

    pub fn write(self: *const ElementCollection, writer: anytype, indent: usize) !void {
        if (self.list.items.len > 0) {
            try writeIndent(writer, indent);
            try self.list.items[0].write(writer);
        }
        if (self.list.items.len > 1) {
            for (self.list.items[1..]) |item| {
                try writer.writeByte('\n');
                try writeIndent(writer, indent);
                try item.write(writer);
            }
        }
    }
};

pub const Entry = struct {
    elements: *ElementCollection,
    allocator: std.mem.Allocator,

    pub fn addOrSet(self: *Entry, name: []const u8, el: Element) !void {
        try self.elements.addOrSet(name, el);
    }
    pub fn set(self: *Entry, name: []const u8, el: Element) !void {
        try self.elements.set(name, el);
    }
    pub fn add(self: *Entry, name: []const u8, el: Element) !void {
        try self.elements.add(name, el);
    }
    pub fn setAuthor(self: *Entry, text: []const u8) !void {
        try self.addOrSet("author", .{ .text = text });
    }
    pub fn setTitle(self: *Entry, text: []const u8) !void {
        try self.addOrSet("title", .{ .text = text });
    }
    pub fn setPublished(self: *Entry, text: []const u8) !void {
        try self.addOrSet("published", .{ .text = text });
    }
    pub fn setId(self: *Entry, text: []const u8) !void {
        try self.addOrSet("id", .{ .text = text });
    }
    pub fn newField(self: *Entry, name: []const u8, text: []const u8) !*Element {
        try self.add(name, .{});
        const ptr = &self.elements.list.items[self.elements.list.items.len - 1];
        ptr.element.attributes = StringMap.init(self.allocator);
        ptr.element.text = text;
        return &ptr.element;
    }
    pub fn newLink(self: *Entry, href: []const u8) !*Element {
        try self.add("link", .{});
        const ptr = &self.elements.list.items[self.elements.list.items.len - 1];
        ptr.element.attributes = StringMap.init(self.allocator);
        ptr.element.text = href;
        return &ptr.element;
    }

    pub fn count(self: *const Entry) usize {
        return self.elements.list.items.len;
    }
};

test "entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var element_list: ElementCollection = .{ .list = ElementList.init(alloc) };
    var entry = Entry{
        .elements = &element_list,
        .allocator = alloc,
    };

    try std.testing.expectError(
        error.UnknownElement,
        entry.set("author", .{ .text = "Alan Sillitoe" }),
    );
    try entry.add("author", .{ .text = "Alan Sillitoe" });
    try entry.add("title", .{ .text = "Sunday Night, Saturday Morning" });
    try entry.set("title", .{ .text = "Saturday Night, Sunday Morning" });
    try std.testing.expectEqual(2, entry.count());

    const ptr = try entry.newLink("https://wikipedia.org");
    try ptr.put("type", "text/html");

    var buffer = std.ArrayList(u8).init(alloc);
    try entry.elements.write(buffer.writer(), 0);

    try std.testing.expectEqualStrings(
        \\<author>Alan Sillitoe</author>
        \\<title>Saturday Night, Sunday Morning</title>
        \\<link type="text/html">https://wikipedia.org</link>
    ,
        buffer.items,
    );
}

pub const Feed = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(ElementCollection),

    elements: ElementCollection,

    pub fn init(allocator: std.mem.Allocator) Feed {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .entries = std.ArrayList(ElementCollection).init(allocator),
            .elements = .{ .list = ElementList.init(allocator) },
        };
    }

    pub fn deinit(self: *Feed) void {
        self.entries.deinit();
        self.elements.list.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn newEntry(self: *Feed) !Entry {
        const ptr = try self.entries.addOne();
        const alloc = self.arena.allocator();
        ptr.list = ElementList.init(alloc);
        return .{ .elements = ptr, .allocator = alloc };
    }

    pub fn write(self: *const Feed, writer: anytype) !void {
        var indent: usize = 0;
        try writer.writeAll("<feed xmlns=\"http://www.w3.org/2005/Atom\">\n");
        indent += 1;
        try self.elements.write(writer, indent);

        for (self.entries.items) |entry| {
            try writer.writeByte('\n');
            try writeIndent(writer, indent);

            try writer.writeAll("<entry>\n");
            try entry.write(writer, indent + 1);

            try writer.writeByte('\n');
            try writeIndent(writer, indent);
            try writer.writeAll("</entry>");
        }

        try writer.writeAll("\n</feed>");
    }

    pub fn addOrSet(self: *Feed, name: []const u8, el: Element) !void {
        try self.elements.addOrSet(name, el);
    }
    pub fn set(self: *Feed, name: []const u8, el: Element) !void {
        try self.elements.set(name, el);
    }
    pub fn add(self: *Feed, name: []const u8, el: Element) !void {
        try self.elements.add(name, el);
    }
    pub fn setAuthor(self: *Feed, text: []const u8) !void {
        try self.addOrSet("author", .{ .text = text });
    }
    pub fn setTitle(self: *Feed, text: []const u8) !void {
        try self.addOrSet("title", .{ .text = text });
    }
    pub fn newLink(self: *Feed, href: []const u8) !*Element {
        try self.add("link", .{});
        const ptr = &self.elements.list.items[self.elements.list.items.len - 1];
        ptr.element.attributes = StringMap.init(self.allocator);
        ptr.element.text = href;
        return &ptr.element;
    }
};

test "feed" {
    const alloc = std.testing.allocator;

    var feed = Feed.init(alloc);
    defer feed.deinit();

    try feed.setTitle("Books");
    try feed.setAuthor("Fergus");

    try std.testing.expectEqual(2, feed.elements.list.items.len);

    var entry = try feed.newEntry();
    try entry.setAuthor("Shelagh Delaney");
    try entry.setTitle("Taste of Honey");

    const ptr = try entry.newField("content", "Hello World");
    try ptr.put("type", "text/html");

    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    try feed.write(buffer.writer());

    try std.testing.expectEqualStrings(
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <title>Books</title>
        \\  <author>Fergus</author>
        \\  <entry>
        \\    <author>Shelagh Delaney</author>
        \\    <title>Taste of Honey</title>
        \\    <content type="text/html">Hello World</content>
        \\  </entry>
        \\</feed>
    ,
        buffer.items,
    );
}
