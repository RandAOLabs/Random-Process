return {
    source_dir = "src",
    include_dir = { "src/typedefs", "src/", "packages/" },
    include = {
        "**/**.tl",
    },
    --[[   scripts = {
        build = {
            post = {
                "scripts/copy_lua_packages.lua",
            },
        },
    }, ]]
    build_dir = "build",
    global_env_def = "ao",
   -- module_name = "vrf",
    gen_target = "5.3",
}
