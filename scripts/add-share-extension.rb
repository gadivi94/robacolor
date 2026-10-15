# Añade al proyecto de Xcode (generado por Capacitor en la nube) la extensión «Compartir → StealColor».
# Solo se usa si en codemagic.yaml SHARE_EXTENSION = "1" (hace falta el App Group en Apple Developer).
require 'xcodeproj'
require 'fileutils'

APP_ID = 'cat.gadivi.robacolor'
EXT_ID = "#{APP_ID}.share"
proj_path = 'ios/App/App.xcodeproj'
project = Xcodeproj::Project.open(proj_path)
app = project.targets.find { |t| t.name == 'App' } or abort('✖ No encuentro el target App')
if project.targets.any? { |t| t.name == 'Share' }
  puts '✔ La extensión ya estaba añadida'
  exit 0
end

# Archivos de la extensión dentro de ios/App/Share
dir = 'ios/App/Share'
FileUtils.mkdir_p(dir)
%w[ShareViewController.swift Info.plist Share.entitlements].each { |f| FileUtils.cp("native/share/#{f}", "#{dir}/#{f}") }
FileUtils.cp('native/share/App.entitlements', 'ios/App/App/App.entitlements')

deploy = app.build_configurations.first.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '15.0'
ext = project.new_target(:app_extension, 'Share', :ios, deploy)
group = project.main_group.new_group('Share', 'Share')
src = group.new_reference('ShareViewController.swift')
group.new_reference('Info.plist')
group.new_reference('Share.entitlements')
ext.add_file_references([src])

# Misma versión y compilación que la app (como en scripts/patch-native.mjs): App Store lo exige
require 'json'
version = ENV['APP_VERSION'] || JSON.parse(File.read('package.json'))['version']
build = (ENV['BUILD_NUMBER'] || '1').to_i.to_s
team = app.build_configurations.first.build_settings['DEVELOPMENT_TEAM']
ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_ID
  s['PRODUCT_NAME'] = 'Share'
  s['INFOPLIST_FILE'] = 'Share/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'Share/Share.entitlements'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = deploy
  s['MARKETING_VERSION'] = version
  s['CURRENT_PROJECT_VERSION'] = build
  s['SKIP_INSTALL'] = 'YES'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['DEVELOPMENT_TEAM'] = team if team
end
app.build_configurations.each { |c| c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/App.entitlements' }
app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save

# El esquema App también compila la extensión (va como dependencia), no hace falta tocarlo
puts "✔ Extensión «Compartir» añadida (#{EXT_ID}, versión #{version} (#{build}))"
