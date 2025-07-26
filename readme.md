a example for using wgpu and fenster in zig
to make wgpu native binding works in nightly version of zig,
you should manually replace callconv(.C) to callconv(.c)
something that the binding does not mentioned is you should link framework Metal when you are on macOS.