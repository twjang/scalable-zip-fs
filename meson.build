project(
  'scalable-zip-fs',
  'cpp',
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3', 'cpp_std=c++20'],
)

build_args = [
  '-DPROJECT_NAME=' + meson.project_name(),
  '-DPROJECT_VERSION=' + meson.project_version(),
]


platform = host_machine.system()
if platform != 'linux'
  error('Only linux is supported.')
endif


dependencies = [
  dependency('fuse3'),
  dependency('zlib'),
  dependency('libzip'),
]

sources = [
  'src/main.cpp',
  'src/zipent.cpp',
  'src/utils.cpp',
  'src/fuse_ops.cpp',
]

incdir = include_directories('include')


exe = executable(
  'scalable-zip-fs',
  sources,
  install : true,
  dependencies : dependencies,
  include_directories: incdir,
  c_args: build_args,
)

# ZIP optimizer tool
optimizer_deps = [
  dependency('zlib'),
  dependency('libzip'),
]

optimizer_exe = executable(
  'zip-optimizer',
  'src/zip_optimizer.cpp',
  install : true,
  dependencies : optimizer_deps,
  c_args: build_args,
)

test('basic', exe)
