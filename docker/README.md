# Container development
The compiler service downloads a pinned Zig release inside its image and watches source edits. The web service serves static files and the shared build volume. Keep toolchains off the host. Publish successful builds atomically; retain the last build on compiler errors.
