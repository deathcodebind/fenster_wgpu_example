const std = @import("std");
const fenster_demo = @import("fenster_demo");
const fenster = fenster_demo.fenster;
const wgpu = @import("wgpu");

fn handleBufferMap(status: wgpu.MapAsyncStatus, _: wgpu.StringView, userdata1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    std.log.info("buffer_map status={x:.8}\n", .{@intFromEnum(status)});
    const complete: *bool = @ptrCast(@alignCast(userdata1 orelse unreachable));
    complete.* = true;
}

fn Window(comptime width: u32, comptime height: u32) type {
    return struct {
        pub const output_extent = wgpu.Extent3D{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        };
        pub const output_bytes_per_row = output_extent.width * 4;
        pub const output_size = output_bytes_per_row * output_extent.height;
        const Self = @This();
        window_instance: fenster.fenster,
        wgpu_instance: *wgpu.Instance,
        wgpu_adapter: *wgpu.Adapter,
        wgpu_device: *wgpu.Device,
        wgpu_queue: *wgpu.Queue,
        wgpu_target_texture: *wgpu.Texture,
        wgpu_target_view: *wgpu.TextureView,
        wgpu_shader_module: *wgpu.ShaderModule,
        wgpu_staging_buffer: *wgpu.Buffer,
        wgpu_render_pipeline: *wgpu.RenderPipeline,
        pub fn writeBuffer(self: *Self, wgpu_buffer: []u32) !void {
            // if (wgpu_buffer.len != Self.output_size) return error.InvalidBufferSize;
            self.window_instance.buf = wgpu_buffer.ptr;
        }
        pub fn init() !Self {
            const instance = wgpu.Instance.create(null).?;
            const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{}, 0);
            const adapter = switch (adapter_request.status) {
                .success => adapter_request.adapter.?,
                else => return error.NoAdapter,
            };
            const device_request = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
                .required_limits = null,
            }, 0);

            const device = switch (device_request.status) {
                .success => device_request.device.?,
                else => return error.NoDevice,
            };

            const queue = device.getQueue().?;
            // fenster use rgba8_unorm_srgb
            const swap_chain_format = wgpu.TextureFormat.rgba8_unorm_srgb;
            const target_texture = device.createTexture(&wgpu.TextureDescriptor{
                .label = wgpu.StringView.fromSlice("render target"),
                .size = output_extent,
                .format = swap_chain_format,
                .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
            }).?;

            const target_texture_view = target_texture.createView(&wgpu.TextureViewDescriptor{
                .label = wgpu.StringView.fromSlice("render target view"),
                .mip_level_count = 1,
                .array_layer_count = 1,
            }).?;

            const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
                .code = @embedFile("./shader.wgsl"),
            })).?;

            const staging_buffer = device.createBuffer(&wgpu.BufferDescriptor{
                .label = wgpu.StringView.fromSlice("staging buffer"),
                .usage = wgpu.BufferUsages.map_read | wgpu.BufferUsages.copy_dst,
                .size = Self.output_size,
                .mapped_at_creation = @as(u32, @intFromBool(false)),
            }).?;

            const color_targets = &[_]wgpu.ColorTargetState{
                wgpu.ColorTargetState{
                    .format = swap_chain_format,
                    .blend = &wgpu.BlendState{
                        .color = wgpu.BlendComponent{
                            .operation = .add,
                            .src_factor = .src_alpha,
                            .dst_factor = .one_minus_src_alpha,
                        },
                        .alpha = wgpu.BlendComponent{
                            .operation = .add,
                            .src_factor = .zero,
                            .dst_factor = .one,
                        },
                    },
                },
            };

            const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
                .vertex = wgpu.VertexState{
                    .module = shader_module,
                    .entry_point = wgpu.StringView.fromSlice("vs_main"),
                },
                .primitive = wgpu.PrimitiveState{},
                .fragment = &wgpu.FragmentState{
                    .module = shader_module,
                    .entry_point = wgpu.StringView.fromSlice("fs_main"),
                    .target_count = color_targets.len,
                    .targets = color_targets.ptr,
                },
                .multisample = wgpu.MultisampleState{},
            }).?;
            var buffer = [_]u32{0} ** (width * height);
            return Self{
                .window_instance = std.mem.zeroInit(fenster.fenster, .{
                    .width = width,
                    .height = height,
                    .title = "hello",
                    .buf = &buffer[0],
                }),
                .wgpu_instance = instance,
                .wgpu_adapter = adapter,
                .wgpu_device = device,
                .wgpu_queue = queue,
                .wgpu_target_texture = target_texture,
                .wgpu_target_view = target_texture_view,
                .wgpu_shader_module = shader_module,
                .wgpu_render_pipeline = pipeline,
                .wgpu_staging_buffer = staging_buffer,
            };
        }
        pub fn open(self: *Self) void {
            _ = fenster.fenster_open(&self.window_instance);
        }
        pub fn close(self: *Self) void {
            defer self.wgpu_instance.release();
            defer self.wgpu_adapter.release();
            defer self.wgpu_device.release();
            defer self.wgpu_queue.release();
            defer self.wgpu_target_texture.release();
            defer self.wgpu_target_view.release();
            defer self.wgpu_shader_module.release();
            defer self.wgpu_render_pipeline.release();
            fenster.fenster_close(&self.window_instance);
        }
    };
}

pub fn main() !void {
    const W = Window(640, 480);
    var f = try W.init();
    f.open();
    defer f.close();
    while (fenster.fenster_loop(&f.window_instance) == 0) {
        // Exit when Escape is pressed
        if (f.window_instance.keys[27] != 0) {
            break;
        }
        const next_texture = f.wgpu_target_view;
        const encoder = f.wgpu_device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("command encoder"),
        }).?;
        defer encoder.release();
        const color_attachments = &[_]wgpu.ColorAttachment{wgpu.ColorAttachment{
            .view = next_texture,
            .clear_value = wgpu.Color{},
        }};
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = color_attachments.ptr,
        }).?;

        render_pass.setPipeline(f.wgpu_render_pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();

        render_pass.release();

        // defer next_texture.release();

        const img_copy_src = wgpu.TexelCopyTextureInfo{
            .origin = wgpu.Origin3D{},
            .texture = f.wgpu_target_texture,
        };
        const img_copy_dst = wgpu.TexelCopyBufferInfo{
            .layout = wgpu.TexelCopyBufferLayout{
                .bytes_per_row = W.output_bytes_per_row,
                .rows_per_image = W.output_extent.height,
            },
            .buffer = f.wgpu_staging_buffer,
        };
        encoder.copyTextureToBuffer(&img_copy_src, &img_copy_dst, &W.output_extent);

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("command buffer"),
        }).?;

        defer command_buffer.release();

        f.wgpu_queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});

        var buffer_map_complete = false;
        _ = f.wgpu_staging_buffer.mapAsync(wgpu.MapModes.read, 0, W.output_size, wgpu.BufferMapCallbackInfo{
            .callback = handleBufferMap,
            .userdata1 = @ptrCast(@constCast(&buffer_map_complete)),
        });
        f.wgpu_instance.processEvents();
        while (!buffer_map_complete) {
            f.wgpu_instance.processEvents();
        }
        const buf: [*]u32 = @ptrCast(@alignCast(f.wgpu_staging_buffer.getMappedRange(0, W.output_size).?));
        defer f.wgpu_staging_buffer.unmap();
        try f.writeBuffer(buf[0..(W.output_size / 4)]);
    }
}
