# frozen_string_literal: true

class BarcodeRegionCropper
  def self.crop_top_region(filepath, ratio: 0.4)
    require "mini_magick"

    img = MiniMagick::Image.open(filepath)
    width  = img.width
    height = img.height
    crop_h = (height * ratio).to_i

    tmp = Tempfile.new(["bcbp_top", ".png"])
    tmp.close

    img.crop "#{width}x#{crop_h}+0+0"
    img.write tmp.path

    tmp.path
  end
end
