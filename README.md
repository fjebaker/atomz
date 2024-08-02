# atomz

An Atom feed generator for Zig.

```zig
const std = @import("std");
const atomz = @import("atomz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var feed = atomz.Feed.init(allocator);
    defer feed.deinit();

    try feed.setTitle("My new feed");
    try feed.setAuthor("Syliva");

    var entry = try feed.newEntry();
    try entry.setTitle("The conquest of cake");

    const ptr = try entry.newField("content", "This would be the content.");
    try ptr.put("type", "text/html");

    try feed.write(std.io.getStdOut().writer());
}
```

This will output the following:

```
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>My new feed</title>
  <author>Syliva</author>
  <entry>
    <title>The conquest of cake</title>
    <content type="text/html">This would be the content.</content>
  </entry>
</feed>
```

