# Workarounds for react-native-readium's Minizip module compilation.
#
# Minizip is a C library whose headers contain extern "C" blocks.
# react-native-readium's Nitro integration sets SWIFT_OBJC_INTEROP_MODE=objcxx,
# which causes clang to compile Minizip as a C++ module. This breaks because
# the extern "C" blocks import other modules (zlib, submodules), which is not
# allowed in that context.
#
# This is needed regardless of whether use_frameworks! is enabled, because
# `pod 'Minizip', modular_headers: true` also generates a modulemap.
#
# Call this from your Podfile's post_install block:
#
#   require_relative '../node_modules/react-native-readium/scripts/readium_post_install'
#
#   post_install do |installer|
#     react_native_post_install(installer, ...)
#     readium_post_install(installer)
#   end
#
def patch_readium_publication_media_loader(installer)
  old_code = [
    '        guard',
    '            let link = publication.linkWithHREF(href),',
    '            let resource = publication.get(link)',
    '        else {',
    '            return nil',
    '        }',
  ].join("\n")

  new_code = [
    '        let link: Link?',
    '        if let matched = publication.linkWithHREF(href) {',
    '            link = matched',
    '        } else if let baseURL = publication.baseURL {',
    '            // AVPlayer requests use absolute URLs (readiumhttp://host/.../file.mp3) while',
    '            // manifests often declare relative reading-order hrefs (e.g. "chapter.mp3").',
    '            link = publication.readingOrder.first { readingLink in',
    '                readingLink.url(relativeTo: baseURL).normalized == href',
    '            }',
    '        } else {',
    '            link = nil',
    '        }',
    '',
    '        guard',
    '            let link = link,',
    '            let resource = publication.get(link)',
    '        else {',
    '            return nil',
    '        }',
  ].join("\n")

  Dir.glob(File.join(installer.sandbox.root, 'ReadiumNavigator/**/PublicationMediaLoader.swift')).each do |path|
    contents = File.read(path)
    next if contents.include?('readingLink.url(relativeTo: baseURL)')

    unless contents.include?(old_code)
      warn "[react-native-readium] PublicationMediaLoader patch skipped (unexpected source in #{path})"
      next
    end

    File.write(path, contents.sub(old_code, new_code))
    puts "[react-native-readium] Patched PublicationMediaLoader for streamed audiobook URLs (#{path})"
  end
end

def readium_post_install(installer)
  patch_readium_publication_media_loader(installer)
  # Rewrite the Minizip modulemap to drop submodules and mark as [extern_c] [system].
  # The modulemap path differs depending on whether use_frameworks! is active:
  #   - With use_frameworks!:  Target Support Files/Minizip/Minizip.modulemap
  #   - Without (modular_headers): Headers/Public/Minizip/Minizip.modulemap
  modulemap_content = <<~MODULEMAP
    module Minizip [extern_c] [system] {
      header "Minizip-umbrella.h"
      export *
    }
  MODULEMAP

  framework_modulemap_content = <<~MODULEMAP
    framework module Minizip [extern_c] [system] {
      umbrella header "Minizip-umbrella.h"
      export *
    }
  MODULEMAP

  # use_frameworks! path
  framework_path = File.join(installer.sandbox.root, 'Target Support Files', 'Minizip', 'Minizip.modulemap')
  # modular_headers path
  headers_path = File.join(installer.sandbox.root, 'Headers', 'Public', 'Minizip', 'Minizip.modulemap')

  if File.exist?(framework_path)
    File.write(framework_path, framework_modulemap_content)
  end

  if File.exist?(headers_path)
    File.write(headers_path, modulemap_content)
  end

  # Suppress the remaining module-import-in-extern-c diagnostic for zlib imports.
  installer.pods_project.targets.each do |target|
    if target.name == 'Minizip'
      target.build_configurations.each do |config|
        config.build_settings['OTHER_CFLAGS'] ||= '$(inherited)'
        config.build_settings['OTHER_CFLAGS'] += ' -Wno-module-import-in-extern-c'
        config.build_settings['OTHER_CPLUSPLUSFLAGS'] ||= '$(inherited)'
        config.build_settings['OTHER_CPLUSPLUSFLAGS'] += ' -Wno-module-import-in-extern-c'
      end
    end

    if target.name == 'fmt'
      target.build_configurations.each do |config|
        # fmt 11's C++20 consteval path fails with newer Apple clang builds
        # used by recent Xcode/iOS simulator SDKs. React Native does not need
        # C++20 for this pod, so keep fmt on C++17.
        config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
      end
    end
  end
end
