# chimera-core-tic80: the fantasy computer TIC-80 in miniBox's sandbox, as a
# Chimera core.
#
# Native reference build (run-native + run-wbx under the build directory):
#     meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
# Guest (core.wbx) build via the cross file waterbox/setup-guest.sh writes:
#     sh waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest core.wbx
#
# Upstream builds with CMake. The lists below are what its CMake compiles for
# the TIC-80 machine and its programming languages (configured with
# -DBUILD_SDL=OFF -DBUILD_LIBRETRO=ON -DBUILD_STATIC=ON -DBUILD_WITH_ALL=ON),
# each language a library with the include folders and definitions upstream
# gives it. Left out: upstream's editors, its game browser and its network
# client (naett), which the machine does not use, and Ruby, whose build needs
# Ruby's own tools (rake). The machine is driven by waterbox/cinterface.c
# through TIC-80's own API (include/tic80.h). Both flavours compile the SAME
# sources; only emulibc.h differs (waterbox/native-shim for the reference).
project('chimera-core-tic80', 'c', 'cpp',
  default_options: ['c_std=gnu11', 'cpp_std=gnu++17', 'optimization=2', 'debug=false', 'warning_level=0'])

t = 'extern/tic80'
v = t / 'vendor'

# the submodule pin is upstream as it is; the patches are laid over it
# (waterbox/apply-patches.sh does nothing to a tree that has them)
run_command(files('waterbox/apply-patches.sh'), check: true)

mb = get_option('minibox_dir')
if mb == ''
  mb_candidate = meson.current_source_dir() / '../chimera/extern/chimera-common-minibox'
  if import('fs').is_dir(mb_candidate)
    mb = mb_candidate
  else
    error('pass -Dminibox_dir=<miniBox checkout> (or keep one at ../chimera/extern/chimera-common-minibox)')
  endif
endif

# one answer from a floating-point expression on every machine: no fused
# multiply-adds; signed overflow wraps, as the script engines expect
common = ['-DCHIMERA_CORE', '-Dd_m3LogOutput=0', '-DNDEBUG', '-fwrapv', '-fno-strict-aliasing', '-ffp-contract=off']
add_project_arguments(common, language: ['c', 'cpp'])

# what each language's part of TIC-80 is compiled with (upstream's CMake)
tic = ['-DTIC_RUNTIME_STATIC', '-DBUILD_DEPRECATED']
def_inc = include_directories(t / 'include', t / 'src')
langs = [
  '-DTIC_BUILD_WITH_LUA', '-DTIC_BUILD_WITH_MOON', '-DTIC_BUILD_WITH_FENNEL', '-DTIC_BUILD_WITH_YUE',
  '-DTIC_BUILD_WITH_JS=1', '-DTIC_BUILD_WITH_SQUIRREL=1', '-DTIC_BUILD_WITH_SCHEME=1',
  '-DTIC_BUILD_WITH_WREN=1', '-DTIC_BUILD_WITH_WASM=1', '-DTIC_BUILD_WITH_JANET=1',
  '-DTIC_BUILD_WITH_PYTHON=1', '-DTIC_BUILD_WITH_MINISCRIPT', '-DTIC_BUILD_WITH_FORTH=1',
]

# TIC-80's version, as upstream's CMake writes it for the commit the
# submodule is at (cmake/version.cmake asks git; here it is written down, so
# that the build is the same wherever it is made). Moving the submodule moves
# these.
version_h = configure_file(input: t / 'version.h.in', output: 'version.h', configuration: {
  'VERSION_MAJOR': 1, 'VERSION_MINOR': 3, 'VERSION_REVISION': 3176, 'VERSION_STATUS': '-dev',
  'VERSION_IS_RELEASE_C': 0, 'VERSION_DIR': '1.3', 'VERSION_BUILD': '', 'VERSION_YEAR': '2026',
  'VERSION_HASH': '3801892'})

# libpng's configuration header, as upstream's CMake writes it
pnglibconf = configure_file(input: v / 'libpng/scripts/pnglibconf.h.prebuilt', output: 'pnglibconf.h', copy: true)

libs = []

libs += static_library('zlib', files(
    v / 'zlib/adler32.c', v / 'zlib/compress.c', v / 'zlib/crc32.c', v / 'zlib/deflate.c', v / 'zlib/inflate.c',
    v / 'zlib/infback.c', v / 'zlib/inftrees.c', v / 'zlib/inffast.c', v / 'zlib/trees.c', v / 'zlib/uncompr.c',
    v / 'zlib/zutil.c'))

png_src = []
foreach n : ['png.c', 'pngerror.c', 'pngget.c', 'pngmem.c', 'pngpread.c', 'pngread.c', 'pngrio.c', 'pngrtran.c',
             'pngrutil.c', 'pngset.c', 'pngtrans.c', 'pngwio.c', 'pngwrite.c', 'pngwtran.c', 'pngwutil.c']
  png_src += v / 'libpng' / n
endforeach
libs += static_library('png', files(png_src) + [pnglibconf],
  c_args: ['-DPNG_ARM_NEON_OPT=0'], include_directories: include_directories(v / 'zlib'))

libs += static_library('blipbuf', files(v / 'blip-buf/blip_buf.c'))

gif_src = []
foreach n : ['dgif_lib.c', 'egif_lib.c', 'gif_err.c', 'gif_font.c', 'gif_hash.c', 'gifalloc.c', 'openbsd-reallocarray.c']
  gif_src += v / 'giflib' / n
endforeach
libs += static_library('giflib', files(gif_src), include_directories: include_directories(v / 'giflib'))

# the machine
core_src = []
foreach n : ['fftdata.c', 'vqtdata.c', 'core/core.c', 'core/draw.c', 'core/io.c', 'core/sound.c', 'tic.c', 'cart.c',
             'tools.c', 'zip.c', 'tilesheet.c', 'script.c', 'ext/fft.c', 'ext/vqt.c', 'ext/vqt_kernel.c',
             'ext/kiss_fft.c', 'ext/kiss_fftr.c', 'ext/png.c', 'ext/gif.c',
             # one copy for every language
             'api/parse_note.c']
  core_src += t / 'src' / n
endforeach
# TIC80_FFT_UNSUPPORTED leaves out the capture of the computer's sound for a
# cart's fft() and vqt() (miniaudio, which opens sound devices): only
# TIC-80's own program turns it on (its --fft option), and a machine may not
# hear the room it is in. fft() and vqt() then read silence.
libs += static_library('tic80core', files(core_src) + [pnglibconf],
  c_args: tic + langs + ['-DTIC80_FFT_UNSUPPORTED'],
  include_directories: [def_inc, include_directories(v / 'moonscript', v / 'fennel', v / 'yuescript', v / 'libpng',
    v / 'blip-buf', v / 'zlib', v / 'lua', v / 's7', v / 'squirrel/include', v / 'wren/src/include', v / 'giflib',
    v / 'wasm3/source')])

# Lua, and the languages that are compiled to Lua (MoonScript, Fennel, YueScript)
lua_src = []
foreach n : ['lapi.c', 'lcode.c', 'lctype.c', 'ldebug.c', 'ldo.c', 'ldump.c', 'lfunc.c', 'lgc.c', 'llex.c', 'lmem.c',
             'lobject.c', 'lopcodes.c', 'lparser.c', 'lstate.c', 'lstring.c', 'ltable.c', 'ltm.c', 'lundump.c',
             'lvm.c', 'lzio.c', 'lauxlib.c', 'lbaselib.c', 'lcorolib.c', 'ldblib.c', 'liolib.c', 'lmathlib.c',
             'loslib.c', 'lstrlib.c', 'ltablib.c', 'lutf8lib.c', 'loadlib.c', 'linit.c', 'lbitlib.c']
  lua_src += v / 'lua' / n
endforeach
lua_inc = include_directories(v / 'lua')
libs += static_library('luaapi', files(lua_src) + files(t / 'src/api/luaapi.c'),
  c_args: tic + ['-DLUA_COMPAT_5_2'], include_directories: [lua_inc, def_inc])
libs += static_library('lua', files(t / 'src/api/lua.c'), c_args: tic, include_directories: [lua_inc, def_inc])
lpeg_src = []
foreach n : ['lpcap.c', 'lpcode.c', 'lpprint.c', 'lptree.c', 'lpvm.c', 'lpcset.c']
  lpeg_src += v / 'lpeg' / n
endforeach
libs += static_library('lpeg', files(lpeg_src), include_directories: lua_inc)
libs += static_library('moon', files(t / 'src/api/moonscript.c'), c_args: tic,
  include_directories: [include_directories(v / 'moonscript'), lua_inc, def_inc])
libs += static_library('fennel', files(t / 'src/api/fennel.c'), c_args: tic,
  include_directories: [include_directories(v / 'fennel'), lua_inc, def_inc])
yue_src = []
foreach n : ['ast.cpp', 'parser.cpp', 'yue_ast.cpp', 'yue_parser.cpp', 'yue_compiler.cpp', 'yuescript.cpp']
  yue_src += v / 'yuescript/src/yuescript' / n
endforeach
libs += static_library('yuescript', files(yue_src) + files(t / 'src/api/yue.cpp'),
  cpp_args: tic + ['-DYUE_NO_MACRO', '-DYUE_UTF8_IMPL'],
  include_directories: [include_directories(v / 'yuescript/src', v / 'yuescript/src/3rdParty',
    v / 'yuescript/src/yuescript', t / 'src/api'), lua_inc, def_inc])

# JavaScript (QuickJS)
libs += static_library('quickjs', files(v / 'quickjs/quickjs.c', v / 'quickjs/libregexp.c', v / 'quickjs/libunicode.c',
    v / 'quickjs/dtoa.c'),
  c_args: ['-D_GNU_SOURCE', '-funsigned-char'], include_directories: include_directories(v / 'quickjs'))
libs += static_library('js', files(t / 'src/api/js.c'), c_args: tic,
  include_directories: [def_inc, include_directories(v / 'quickjs')])

# Squirrel
sq_src = []
foreach n : ['squirrel/sqapi.cpp', 'squirrel/sqbaselib.cpp', 'squirrel/sqclass.cpp', 'squirrel/sqcompiler.cpp',
             'squirrel/sqdebug.cpp', 'squirrel/sqfuncstate.cpp', 'squirrel/sqlexer.cpp', 'squirrel/sqmem.cpp',
             'squirrel/sqobject.cpp', 'squirrel/sqstate.cpp', 'squirrel/sqtable.cpp', 'squirrel/sqvm.cpp',
             'sqstdlib/sqstdaux.cpp', 'sqstdlib/sqstdblob.cpp', 'sqstdlib/sqstdio.cpp', 'sqstdlib/sqstdmath.cpp',
             'sqstdlib/sqstdrex.cpp', 'sqstdlib/sqstdstream.cpp', 'sqstdlib/sqstdstring.cpp',
             'sqstdlib/sqstdsystem.cpp']
  sq_src += v / 'squirrel' / n
endforeach
libs += static_library('squirrel', files(sq_src) + files(t / 'src/api/squirrel.c'),
  c_args: tic, cpp_args: tic,
  include_directories: [include_directories(v / 'squirrel/include', v / 'squirrel/squirrel', v / 'squirrel/sqstdlib'),
    def_inc])

# Scheme (s7). s7 saves and restores the signal mask around its errors
# (sigsetjmp); the sandbox's C library has no signals, and no sigsetjmp, so
# s7 is given the plain setjmp, in both builds.
s7_jmp = ['-Dsigsetjmp(b,m)=setjmp(b)', '-Dsiglongjmp=longjmp', '-Dsigjmp_buf=jmp_buf']
libs += static_library('scheme', files(v / 's7/s7.c', t / 'src/api/scheme.c'), c_args: tic + s7_jmp,
  include_directories: [include_directories(v / 's7'), def_inc])

# Wren
wren_src = []
foreach n : ['optional/wren_opt_meta.c', 'optional/wren_opt_random.c', 'vm/wren_compiler.c', 'vm/wren_core.c',
             'vm/wren_debug.c', 'vm/wren_primitive.c', 'vm/wren_utils.c', 'vm/wren_value.c', 'vm/wren_vm.c']
  wren_src += v / 'wren/src' / n
endforeach
libs += static_library('wren', files(wren_src) + files(t / 'src/api/wren.c'), c_args: tic,
  include_directories: [include_directories(v / 'wren/src/include', v / 'wren/src/optional', v / 'wren/src/vm'),
    def_inc])

# WebAssembly (wasm3)
wasm_src = []
foreach n : ['m3_bind.c', 'm3_code.c', 'm3_compile.c', 'm3_core.c', 'm3_parse.c', 'm3_env.c', 'm3_exec.c',
             'm3_function.c', 'm3_info.c', 'm3_module.c']
  wasm_src += v / 'wasm3/source' / n
endforeach
libs += static_library('wasm', files(wasm_src) + files(t / 'src/api/wasm.c'), c_args: tic,
  include_directories: [include_directories(v / 'wasm3/source'), def_inc])

# Janet: janet.c is written by Janet itself (waterbox/make-janet.sh)
janet_c = custom_target('janet.c',
  output: 'janet.c',
  command: [files('waterbox/make-janet.sh'), meson.current_source_dir() / v / 'janet', '@OUTPUT@',
            meson.current_build_dir() / 'janet-work'])
libs += static_library('janet', [janet_c] + files(t / 'src/api/janet.c'), c_args: tic,
  include_directories: [include_directories(v / 'janet/src/include', t / 'build/janet'), def_inc])

# Python (pocketpy)
py_src = []
foreach n : ['bindings/py_array.c', 'bindings/py_mappingproxy.c', 'bindings/py_method.c', 'bindings/py_number.c',
             'bindings/py_object.c', 'bindings/py_property.c', 'bindings/py_range.c', 'bindings/py_str.c',
             'common/_generated.c', 'common/algorithm.c', 'common/chunkedvector.c', 'common/memorypool.c',
             'common/name.c', 'common/serialize.c', 'common/smallmap.c', 'common/socket.c', 'common/sourcedata.c',
             'common/sstream.c', 'common/str.c', 'common/threads.c', 'common/vector.c', 'compiler/compiler.c',
             'compiler/lexer.c', 'debugger/core.c', 'debugger/dap.c', 'interpreter/ceval.c', 'interpreter/dll.c',
             'interpreter/frame.c', 'interpreter/generator.c', 'interpreter/heap.c', 'interpreter/line_profiler.c',
             'interpreter/objectpool.c', 'interpreter/py_compile.c', 'interpreter/typeinfo.c', 'interpreter/vm.c',
             'interpreter/vmx.c', 'modules/array2d.c', 'modules/base64.c', 'modules/builtins.c',
             'modules/colorcvt.c', 'modules/conio.c', 'modules/dis.c', 'modules/easing.c', 'modules/enum.c',
             'modules/gc.c', 'modules/importlib.c', 'modules/inspect.c', 'modules/json.c', 'modules/lz4.c',
             'modules/math.c', 'modules/os.c', 'modules/pickle.c', 'modules/picoterm.c', 'modules/pkpy.c',
             'modules/random.c', 'modules/stdc.c', 'modules/time.c', 'modules/traceback.c',
             'modules/unicodedata.c', 'modules/vmath.c', 'objects/bintree.c', 'objects/codeobject.c',
             'objects/codeobject_ser.c', 'objects/container.c', 'objects/namedict.c', 'objects/object.c',
             'public/Bindings.c', 'public/CodeExecution.c', 'public/DictSlots.c', 'public/FrameOps.c',
             'public/GlobalSetup.c', 'public/Inspection.c', 'public/ModuleSystem.c', 'public/PyDict.c',
             'public/PyException.c', 'public/PyList.c', 'public/PySlice.c', 'public/PyTuple.c',
             'public/PythonOps.c', 'public/StackOps.c', 'public/TypeSystem.c', 'public/ValueCast.c',
             'public/ValueCreation.c']
  py_src += v / 'pocketpy/src' / n
endforeach
py_defs = ['-DPK_ENABLE_CUSTOM_SNAME=0', '-DPK_ENABLE_DETERMINISM=0', '-DPK_ENABLE_MIMALLOC=0', '-DPK_ENABLE_OS=0',
           '-DPK_ENABLE_THREADS=0', '-DPK_ENABLE_WATCHDOG=0']
libs += static_library('pocketpy', files(py_src), c_args: py_defs,
  include_directories: include_directories(v / 'pocketpy/include'))
libs += static_library('python', files(t / 'src/api/python.c'), c_args: tic + py_defs,
  include_directories: [include_directories(v / 'pocketpy/include'), def_inc])

# MiniScript
ms_src = []
foreach n : ['cpp/core/CS_List.cpp', 'cpp/core/CS_Math.cpp', 'cpp/core/CS_String.cpp', 'cpp/core/CS_value_util.cpp',
             'cpp/core/StringStorage.cpp', 'cpp/core/hashing.cpp', 'cpp/core/host_api.cpp',
             'cpp/core/unicodeUtil.cpp', 'cpp/core/value.cpp', 'cpp/core/value_list.cpp', 'cpp/core/value_map.cpp',
             'cpp/core/value_string.cpp', 'cpp/core/vm_error.cpp', 'generated/AST.g.cpp',
             'generated/Bytecode.g.cpp', 'generated/CodeEmitter.g.cpp', 'generated/CodeGenerator.g.cpp',
             'generated/CoreIntrinsics.g.cpp', 'generated/DateTimeUtils.g.cpp', 'generated/Disassembler.g.cpp',
             'generated/ErrorTypes.g.cpp', 'generated/FuncDef.g.cpp', 'generated/GCInterfaces.g.cpp',
             'generated/GCItems.g.cpp', 'generated/GCManager.g.cpp', 'generated/GCSet.g.cpp',
             'generated/Globals.g.cpp', 'generated/IOHelper.g.cpp', 'generated/Interpreter.g.cpp',
             'generated/Intrinsic.g.cpp', 'generated/IntrinsicAPI.g.cpp', 'generated/LangConstants.g.cpp',
             'generated/Lexer.g.cpp', 'generated/PRNG.g.cpp', 'generated/Parselet.g.cpp', 'generated/Parser.g.cpp',
             'generated/StringUtils.g.cpp', 'generated/VM.g.cpp', 'generated/VarMap.g.cpp']
  ms_src += v / 'miniscript2' / n
endforeach
ms_inc = include_directories(v / 'miniscript2/cpp', v / 'miniscript2/cpp/core', v / 'miniscript2/generated')
libs += static_library('libminiscript', files(ms_src) + files(v / 'miniscript2_extras/keyboard.cpp'),
  cpp_args: ['-std=gnu++14'], include_directories: ms_inc)
libs += static_library('miniscript', files(t / 'src/api/miniscript.cpp') + [version_h],
  cpp_args: tic + ['-std=gnu++20'], include_directories: [ms_inc, def_inc])

# Forth (pForth)
pf_src = []
foreach n : ['pf_cglue.c', 'pf_clib.c', 'pf_core.c', 'pf_inner.c', 'pf_io.c', 'pf_io_none.c', 'pf_mem.c',
             'pf_save.c', 'pf_text.c', 'pf_words.c', 'pfcompil.c', 'paging/pagedmem.c', 'paging/lockpage.c',
             'paging/qadmpage.c']
  pf_src += v / 'pforth/csrc' / n
endforeach
libs += static_library('forth', files(pf_src) + files(t / 'src/api/forth.c'),
  c_args: tic + ['-DPF_DEMAND_PAGING=0', '-DPF_NO_FILEIO', '-DPF_STATIC_DIC', '-DPF_SUPPORT_FP'],
  include_directories: [include_directories(v / 'pforth/csrc'), def_inc])

core_sources = files('waterbox/cinterface.c')
core_args = tic + langs
# the built-in cart the player takes its mouse cursors from
core_inc = [def_inc, include_directories(t / 'build/assets')]

if meson.is_cross_build()
  # ---- the guest: core.wbx --------------------------------------------------
  # miniBox's musl and libstdc++ arrive through the cross file. The -u lines
  # name the pthread functions libgcc's unwinder refers to weakly: a weak
  # reference is not enough to pull them out of a static libc, and it would
  # call address zero.
  mbdir = meson.get_external_property('minibox_dir')
  mbuild = meson.get_external_property('minibox_build')
  sr = meson.get_external_property('guest_sysroot')

  executable('core', core_sources + files('waterbox/guest-syscalls.c'),
    name_suffix: 'wbx',
    c_args: core_args,
    include_directories: core_inc,
    link_with: libs,
    link_args: [
      '-static', '-no-pie',
      '-Wl,--eh-frame-hdr', '-Wl,-O2', '-Wl,--no-relax', '-Wl,-z,stack-size=8388608',
      '-T', mbdir / 'source/guest/linkscript.T',
      '-Wl,-u,pthread_once', '-Wl,-u,pthread_cond_wait',
      '-Wl,-u,pthread_cond_broadcast', '-Wl,-u,pthread_key_create',
      '-Wl,-u,pthread_mutexattr_init', '-Wl,-u,pthread_mutexattr_settype',
      '-Wl,-u,pthread_mutexattr_destroy',
      mbuild / 'source/guest/cxxglue.c.o',
      mbuild / 'source/guest/emulibc.c.o',
      '-L' + sr / 'lib', '-lstdc++', '-lgcc', '-lgcc_eh', '-lc'])
else
  # ---- the native reference -------------------------------------------------
  m = meson.get_compiler('c').find_library('m', required: false)
  executable('run-native', core_sources + files('waterbox/run-native.c'),
    c_args: core_args + ['-I' + mb / 'source/guest/include', '-I' + mb / 'extern/jsmn'],
    include_directories: [include_directories('waterbox/native-shim')] + core_inc,
    link_with: libs,
    link_language: 'cpp',
    dependencies: [m])

  mbhost = mb / 'build/meson-linux/source/host'
  executable('run-wbx', files('waterbox/run-wbx.c'),
    c_args: ['-I' + mb / 'source/host'],
    link_args: [mbhost / 'libminiboxhost.so'],
    build_rpath: mbhost)
endif
