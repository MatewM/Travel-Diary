require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'zxing_cpp'
end
require 'zxing_cpp'
require 'mini_magick'

img = MiniMagick::Image.open("/tmp/test_image.jpg")
puts ZXingCPP.read_barcodes(img)
