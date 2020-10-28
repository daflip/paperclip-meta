module Paperclip
  class Attachment
    alias :original_post_process_styles :post_process_styles
    alias :original_save :save

    # If attachment deleted - destroy meta data
    def save
      if (not @queued_for_delete.empty?) and @queued_for_write.empty?
        instance_write(:meta, ActiveSupport::Base64.encode64(Marshal.dump({}))) if instance.respond_to?(:"#{name}_meta=")
      end
      original_save
    end
      
    # If model has #{name}_meta column we getting sizes of processed
    # thumbnails and saving it to #{name}_meta column.
    def post_process_styles
      original_post_process_styles

      if instance.respond_to?(:"#{name}_meta=")
        meta # init

        @queued_for_write.each do |style, file|
          begin
            geo = Geometry.from_file file
            @meta[style] = {:width => geo.width.to_i, :height => geo.height.to_i, :size => File.size(file) }
          rescue NotIdentifiedByImageMagickError => e
            @meta[style] = {}
          end
        end
        @meta = Hash[@meta.sort_by do |meta_style_name,meta_style| 0 - (meta_style[:width].to_i * meta_style[:height].to_i) end]
        instance_write(:meta, ActiveSupport::Base64.encode64(Marshal.dump(@meta)))
      end
    end

    # Meta access methods
    [:width, :height, :size].each do |meth|
      define_method(meth) do |*args|
        style = args.first || default_style
        meta_read(style, meth)
      end
    end

    def srcset(options = {})
      meta # init
      # use srcset if requested..
      @meta.map do  |style_name,meta_attrs| 
        if (not options[:exclude_srcset_styles]) or (not options[:exclude_srcset_styles].include?(style_name))
          "#{self.url(style_name)} #{meta_attrs[:width].to_i}w" 
        end
      end.compact.join(', ')
    end

    # get styles sorted by size from largest to smallest
    # :original if it exists is always first
    def weighted_styles(input)
      Hash[input.sort_by do |meta_style_name,meta_style| 
        r = if meta_style_name == :original 
          -9999999999999
        else
          0 - (meta_style[:width].to_i + meta_style[:height].to_i)
        end
      end]
    end

    def meta_write(meta_data)
      meta # init
      meta_data.each do |style,style_meta_data|
        @meta[style.to_sym] = style_meta_data
      end
      @meta = weighted_styles(@meta)
      instance_write(:meta, ActiveSupport::Base64.encode64(Marshal.dump(@meta)))
    end


    # if this attachment is a remote url (i.e. not local filesystem)
    def remote_url?(style_name = default_style)
      return (meta and meta.has_key?(style_name) and meta[style_name][:url])
    end

    # overwrite paperclips URL so we check meta for a url and use that if it's set
    # otherwise fallback to paperclip standard behavior
    def url(style_name = default_style, use_timestamp = @use_timestamp)                                                                                                                                                           
      if remote_url?(style_name)
        meta[style_name][:url]
      else
        default_url = @default_url.is_a?(Proc) ? @default_url.call(self) : @default_url
        url = original_filename.nil? ? interpolate(default_url, style_name) : interpolate(@url, style_name)
        use_timestamp && updated_at ? [url, updated_at].compact.join(url.include?("?") ? "&" : "?") : url
      end
    end

    def image_size(style = default_style)
      "#{width(style)}x#{height(style)}"
    end

    def meta
      if instance.respond_to?(:"#{name}_meta") && instance_read(:meta)
        @meta ||= Marshal.load(ActiveSupport::Base64.decode64(instance_read(:meta)))
      end
      @meta ||= {}
    end

    private

    def meta_read(style, item)
      meta
      @meta.key?(style) ? @meta[style][item].to_i : nil
    end
  end
end
