require 'json'
require 'net/http'
require 'uri'
require 'elasticsearch'
require 'rexml/document'

REQUEST_TIMEOUT = 5 # request timeout in seconds for connection
RETRY_ON_FAILURE = 2 # num of retries after failure

def register(params)
  @source_field = params["source_field"]
  @cf_host_v = params["cdn_host"]
  @servers = "https://#{params["access_store_host"]}"
  get_elasticsearch_client
end

def filter(event)

  if event.get(@source_field).nil?
    event.tag("#{@source_field}_not_found")
    return [event]
  end

  if event.get(@cf_host_v).nil?
    event.tag("#{@cf_host_v}_not_found")
    return [event]
  else
    @cloudfront_url = "http://#{event.get(@cf_host_v)}"
  end

  if !((event.get(@source_field) =~ /[^\/]+.m3u8$/) || (event.get(@source_field) =~ /[^\/]+.m4a$/) || (event.get(@source_field) =~ /[^\/]+.ogg$/) || (event.get(@source_field) =~ /[^\/]+.aac$/) || (event.get(@source_field) =~ /[^\/]+.ts$/) || (event.get(@source_field) =~ /[^\/]+.mpd$/) || (event.get(@source_field) =~ /[^\/]+init.mp4$/) || (event.get(@source_field) =~ /[^\/]+.mp4$/) || (event.get(@source_field) =~ /[^\/]+.m4f$/) )
    return []
  end

  if ((event.get(@source_field) =~ /[^\/]+.m4a$/) || (event.get(@source_field) =~ /[^\/]+.ogg$/) || (event.get(@source_field) =~ /[^\/]+.aac$/) )
    event.set('type',"audio_only")
    event.set('mimetype', 'm4a') if (event.get(@source_field) =~ /[^\/]+.m4a$/)
    event.set('mimetype', 'ogg') if (event.get(@source_field) =~ /[^\/]+.ogg$/)
    event.set('mimetype', 'aac') if (event.get(@source_field) =~ /[^\/]+.aac$/)
  end
  if event.get('sc_status').to_i >= 400
    return [event]
  end


  if event.get(@source_field) =~ /[^\/]+.m3u8$/
    manifest_url = event.get(@source_field)
    puts "URI #{manifest_url}"
    es_record = check_for_manifest(manifest_url)
    last_record = es_record["hits"]["hits"][0] rescue nil
    parsed = last_record["_source"]["parsed"] unless last_record.nil?
    if last_record
      if parsed
        puts "Master manifest already parsed; Do nothing"
        return [event]
      else
        puts "Seem to be a sub manifest; update the event with the required bitrate and other params"
        # Video specific information
        avg_bw = last_record["_source"]["AVERAGE-BANDWIDTH"]
        bw = !avg_bw.nil? ? avg_bw : last_record["_source"]["BANDWIDTH"]
        codecs = last_record["_source"]["CODECS"]
        frame_rate = last_record["_source"]["FRAME-RATE"]
        resolution = last_record["_source"]["RESOLUTION"]

        #Audio specific information
        #
        type = last_record["_source"]["TYPE"]
        groupId = last_record["_source"]["GROUP-ID"]
        language = last_record["_source"]["LANGUAGE"]
        name = last_record["_source"]["NAME"]
        default = last_record["_source"]["DEFAULT"]
        auto_select = last_record["_source"]["AUTOSELECT"]
        hls_version = last_record["_source"]["hls_version"]

        event.set('bitrate', bw.to_i) if bw
        event.set('type', 'VIDEO') if resolution
        event.set('codecs', codecs) if codecs
        event.set('frame_rate', frame_rate) if frame_rate
        event.set('resolution', resolution) if resolution
        event.set('hls_version', hls_version) if hls_version
        if resolution
          res_split = resolution.split("x")
          if res_split.length == 2
            event.set('width', res_split[0].to_i)
            event.set('height', res_split[1].to_i)
          end
        end
        if bw
          exp_index = get_experiance_index(bw, event.get('sc_bytes'), event.get('time_taken'))
          exp_index = exp_index>1 ? 1 : exp_index
          event.set('exp_index', exp_index.to_f)
        end
        event.set('type', type) if type
        event.set('groupId', groupId) if groupId
        event.set('language', language) if language
        event.set('name', name) if name
        event.set('default', default) if default
        event.set('auto_select', auto_select) if auto_select

        return [event]
      end
    end

    response = get_manifest(manifest_url)
    if response.code == '200'
      if ismaster(response)
        event.set('manifest_type','master')
        variant_manifests_data = parse_hls_manifest(response, manifest_url)
        variant_manifests_data.each do |variant|
          variant_response = get_manifest(variant[:manifest_url])
          variant_manifest_data = parse_hls_variant_manifest(variant_response, manifest_url, true)
          puts "variant manifest data #{variant_manifest_data}"
          variant.merge!(variant_manifest_data)
        end
        write_manifest_to_es(manifest_url, variant_manifests_data) if variant_manifests_data.size > 0
      else
        event.set('manifest_type','variant')
        variant_manifests_data = []
        variant_manifest_data = parse_hls_variant_manifest(response, manifest_url, true)
        segment_url = variant_manifest_data[:segment_syntax]
        puts "Segment URL => #{segment_url}"
        es_record = check_for_segment(segment_url)
        last_record = es_record["hits"]["hits"][0] rescue nil
        puts "Segment record =>#{last_record}"
        if !variant_manifest_data.empty? && last_record.nil?
          puts "Variant Manifest Data => #{variant_manifest_data}"
          variant_manifest_data[:manifest_url] = manifest_url
          variant_manifests_data << variant_manifest_data
          write_manifest_to_es(nil, variant_manifests_data) if variant_manifests_data.size > 0
        end
      end
    end
  elsif (event.get(@source_field) =~ /[^\/]+.ts$/)
    segment_url_orig = event.get(@source_field)
    puts "URI #{segment_url_orig}"
    segment_url = segment_url_orig.gsub(/\d+(?!\/).ts.*/,'')
    puts "Segment URL : #{segment_url}"
    es_record = check_for_segment(segment_url)
    last_record = es_record["hits"]["hits"][0] rescue nil

    if last_record
      avg_bw = last_record["_source"]["AVERAGE-BANDWIDTH"]
      bw = !avg_bw.nil? ? avg_bw : last_record["_source"]["BANDWIDTH"]
      codecs = last_record["_source"]["CODECS"]
      frame_rate = last_record["_source"]["FRAME-RATE"]
      resolution = last_record["_source"]["RESOLUTION"]
      event.set('bitrate', bw.to_i) if bw
      event.set('codecs', codecs) if codecs
      event.set('frame_rate', frame_rate) if frame_rate
      event.set('resolution', resolution) if resolution
      event.set('type',"segment")
      if bw
        exp_index = get_experiance_index(bw, event.get('sc_bytes'), event.get('time_taken'))
        exp_index = exp_index>1 ? 1 : exp_index
        event.set('exp_index', exp_index.to_f)
      end
      return [event]
    else
      return_hash = Hash.new
      stream_info = inspect_segment(segment_url_orig)
      segment_syntax = segment_url_orig.gsub(/\d+(?!\/).ts.*/, '')
      return_hash.merge!(stream_info)
      return_hash[:segment_syntax] = segment_syntax
      event.set('bitrate', stream_info[:BANDWIDTH].to_i)
      event.set('codecs', stream_info[:CODECS])
      event.set('resolution', stream_info[:RESOLUTION])
      puts "ES Payload #{return_hash}"
      payload = {index: 'abr_avails', type: '_doc', body: return_hash}
      @es_client.index payload
      return [event]
    end
  elsif (event.get(@source_field) =~ /[^\/]+.mpd$/) || (event.get(@source_field) =~ /[^\/]+init.mp4$/)
    manifest_url = event.get(@source_field)
    puts "URI #{manifest_url}"
    es_record = check_for_manifest(manifest_url)
    event.set('stream_method', 'DASH') if event.get(@source_field) =~ /[^\/]+.mpd$/
    last_record = es_record["hits"]["hits"][0] rescue nil
    parsed = last_record["_source"]["parsed"] unless last_record.nil?
    if last_record
      if parsed
        puts "Master manifest already parsed; Do nothing"
        return [event]
      else
        puts "Seem to be an init mp4; update the event with the required bitrate and other params"
        # Video specific information
        bw = last_record["_source"]["BANDWIDTH"]
        codecs = last_record["_source"]["CODECS"]
        frame_rate = last_record["_source"]["FRAME-RATE"]
        resolution = last_record["_source"]["RESOLUTION"]

        #Audio specific information
        type = last_record["_source"]["TYPE"]
        language = last_record["_source"]["LANGUAGE"]
        sample_rate = last_record["_source"]["SAMPLE-RATE"]

        event.set('bitrate', bw.to_i) if bw
        event.set('codecs', codecs) if codecs
        event.set('frame_rate', frame_rate) if frame_rate
        event.set('resolution', resolution) if resolution
        if resolution
          res_split = resolution.split("x")
          if res_split.length == 2
            event.set('width', res_split[0].to_i)
            event.set('height', res_split[1].to_i)
          end
        end
        if bw
          exp_index = get_experiance_index(bw, event.get('sc_bytes'), event.get('time_taken'))
          exp_index = exp_index>1 ? 1 : exp_index
          event.set('exp_index', exp_index.to_f)
        end
        event.set('type', type) if type
        event.set('sample_rate', sample_rate) if sample_rate
        event.set('language', language) if language

        return [event]
      end
    end

    response = get_manifest(manifest_url)
    if response.code == '200'
      variant_manifests_data = parse_dash_manifest(response, manifest_url)
      # TODO: Need to find the Bandwidth in this case...
      puts "variant manifest data #{variant_manifests_data}"
      write_manifest_to_es(manifest_url, variant_manifests_data) if variant_manifests_data.size > 0
    end
  elsif (event.get(@source_field) =~ /[^\/]+.mp4$/) || (event.get(@source_field) =~ /[^\/]+.m4f$/)
    segment_url_orig = event.get(@source_field)
    puts "URI #{segment_url_orig}"
    segment_url = segment_url_orig.gsub(/\d+(?!\/).mp4.*/,'') if event.get(@source_field) =~ /[^\/]+.mp4$/
    segment_url = segment_url_orig.gsub(/\d+(?!\/).m4f.*/,'') if event.get(@source_field) =~ /[^\/]+.m4f$/
    puts "Segment URL : #{segment_url}"

    es_record = check_for_segment(segment_url)
    last_record = es_record["hits"]["hits"][0] rescue nil
    if last_record
      bw = last_record["_source"]["BANDWIDTH"]
      codecs = last_record["_source"]["CODECS"]
      frame_rate = last_record["_source"]["FRAME-RATE"]
      resolution = last_record["_source"]["RESOLUTION"]
      event.set('bitrate', bw.to_i) if bw
      event.set('codecs', codecs) if codecs
      event.set('frame_rate', frame_rate) if frame_rate
      event.set('resolution', resolution) if resolution
      event.set('type',"segment")
      if bw
        exp_index = get_experiance_index(bw, event.get('sc_bytes'), event.get('time_taken'))
        exp_index = exp_index>1 ? 1 : exp_index
        event.set('exp_index', exp_index.to_f)
      end
      return [event]
    else
      puts "Segment syntax not found in abr_avails; Not populating bandwidth data"
    end
  end
  [event]
end

def get_experiance_index(br, bytes_delivered, time_taken)
  puts "Calculating expriance Index => #{br} : #{bytes_delivered} : #{time_taken}"
  client_speed =  bytes_delivered.to_f / time_taken.to_f
  puts "Download Speed : #{client_speed}"
  exp_index = ( client_speed.to_f / br.to_f ).round(3)
  puts "Computed Experiance Index => #{exp_index}"
  exp_index
end

def check_for_manifest(manifest_url)
  puts "Checking if the manifest is already parsed #{manifest_url}"
  search_params = {
      "query" => {
          "bool" => {
              "must" => [
                  {"match" => {"manifest_url" => manifest_url}},
              ]
          }
      }
  }

  begin
    payload = {index: 'abr_avails', type: '_doc', body: search_params}
    es_record = @es_client.search payload
  rescue StandardError => e
    puts ("EsDatastore:elasticsearch.failure; Could not write to datastore: #{e.message}")
  end
  return es_record
end

def check_for_segment(segment_url)
  puts "Checking if the segment is already entered #{segment_url}"

  search_params = {
      "query" => {
          "bool" => {
              "must" => [
                  {"match" => {"segment_syntax" => segment_url}},
              ]
          }
      }
  }

  begin
    payload = {index: 'abr_avails', type: '_doc', body: search_params}
    puts "Payload : #{payload}"
    es_record = @es_client.search payload
  rescue StandardError => e
    puts ("EsDatastore:elasticsearch.failure; Could not read from datastore: #{e.message}")
  end
  return es_record
end

def write_manifest_to_es(manifest_url, variant_manifests_data)
  if !manifest_url.nil?
    puts "Variant manifests found, master manifest write on Elastic search"
    params = {parsed: true, manifest_url: manifest_url}
    begin
      payload = {index: 'abr_avails', type: '_doc', body: params}
      @es_client.index payload
    rescue StandardError => e
      puts ("EsDatastore:elasticsearch.failure; Could not write to datastore: #{e.message}")
    end
  end

  puts "Variant manifests found, persist them on Elastic search"
  variant_manifests_data.each do |variant|
    params = variant.to_json
    puts "JSON params #{params}"
    begin
      payload = {index: 'abr_avails', type: '_doc', body: params}
      @es_client.index payload
    rescue StandardError => e
      puts ("EsDatastore:elasticsearch.failure; Could not write to datastore: #{e.message}")
    end
  end
end

def get_manifest(manifest_url)
  cf_url = @cloudfront_url + manifest_url
  puts "CF url #{cf_url}"
  uri = URI.parse(cf_url)
  request = Net::HTTP::Get.new(uri)
  response = Net::HTTP.get_response(uri)
  return response
end

def parse_dash_manifest(response, uri)
  doc = REXML::Document.new(response.body)
  return_data = Array.new

  begin
    doc.elements.each('MPD/Period/AdaptationSet') do |adap_set|
      mimeType = adap_set.attributes["mimeType"] rescue ''
      frame_rate = adap_set.attributes["frameRate"] rescue ''
      lang = adap_set.attributes["lang"] rescue ''

      top_level_segment_template = adap_set.elements['SegmentTemplate']
      if top_level_segment_template
        initialization = top_level_segment_template.attributes['initialization']
        media = top_level_segment_template.attributes['media']
      end

      adap_set.elements.each('Representation') do |representation|
        bandwidth = representation.attributes["bandwidth"]
        codecs = representation.attributes["codecs"]
        height = representation.attributes["height"]
        width = representation.attributes["width"]
        frame_rate = representation.attributes["frameRate"] unless frame_rate
        audio_sample_rate = representation.attributes["audioSamplingRate"]
        rep_segment_template = representation.elements['SegmentTemplate']
        if rep_segment_template
          initialization = rep_segment_template.attributes['initialization']
          media = rep_segment_template.attributes['media']
          media_clone = media.clone
          media_clone.gsub!('$Bandwidth$', bandwidth) if media_clone.include?('$Bandwidth$')
          media_clone.gsub!(/\$Number.*/, '') if media_clone.include?('$Number')
          media_clone.gsub!(/\$Time.*/, '') if media_clone.include?('$Time')
          media_clone.gsub!('$RepresentationID$', representation.attributes["id"]) if media_clone.include?('$RepresentationID$')
        elsif top_level_segment_template
          media_clone = media.clone
          media_clone.gsub!('$Bandwidth$', bandwidth) if media_clone.include?('$Bandwidth$')
          media_clone.gsub!(/\$Number.*/, '') if media_clone.include?('$Number')
          media_clone.gsub!(/\$Time.*/, '') if media_clone.include?('$Time')
          media_clone.gsub!('$RepresentationID$', representation.attributes["id"]) if media_clone.include?('$RepresentationID$')
        end
        puts "Media #{media_clone}"
        split_arr = uri.split('/', -1)
        split_arr.delete_at(split_arr.size - 1)
        sub_manifest_url = split_arr.join('/') + '/' + initialization
        segment_syntax = split_arr.join('/') + '/' + media_clone
        case mimeType
          when "video/mp4"
            value_hash = {
                manifest_url: sub_manifest_url,
                BANDWIDTH: bandwidth,
                CODECS: codecs,
                TYPE: 'VIDEO',
                RESOLUTION: width + 'x' + height,
                segment_syntax: segment_syntax
            }
            value_hash["FRAME-RATE"] = eval(frame_rate) rescue frame_rate
          when "audio/mp4"
            value_hash = {
                manifest_url: sub_manifest_url,
                BANDWIDTH: bandwidth,
                CODECS: codecs,
                TYPE: 'AUDIO',
                LANGUAGE: lang,
                segment_syntax: segment_syntax
            }
            value_hash["SAMPLE-RATE"] = audio_sample_rate
        end
        return_data << value_hash
      end
    end
  rescue Exception => e
    puts ("Exception while reading manifest #{e.backtrace.join("\n")}")
    return []
  end
  return return_data
end

def ismaster(response)
  is_master = false
  reader = StringIO.new(response.body)
  reader.each_line do |ln|
    if ln =~ /^#EXT-X-STREAM-INF:/ || /^#EXT-X-MEDIA:/
      is_master =  true
      break
    elsif ln =~ /^#EXT-X-TARGETDURATION:/ || /^#EXT-X-MEDIA-SEQUENCE:/ || /^#EXT-X-PLAYLIST-TYPE:/ || /^#EXTINF:/
      break
    end
  end
  is_master
end

def parse_hls_manifest(response, uri)
  reader = StringIO.new(response.body)
  return_data = Array.new
  value_hash = Hash.new
  hls_version = 3
  grab_next_line = false
  reader.each_line do |ln|
    if ln =~ /^#EXT-X-VERSION:/
      hls_version = ln.split(':')[1].strip
    elsif ln =~ /^#EXT-X-STREAM-INF:/
      #the next line in the playlist file identifies another variant playlist file.
      values = ln.split(':')[1]
      values = values.scan(/(?:\".*?\"|[^,])+/)
      unless values.empty?
        values.each do |kvpair|
          kv_split = kvpair.split('=')
          if kv_split.length == 2
            key = kv_split[0]
            value = kv_split[1]
            value = value.gsub("\"", "")
            value_hash[key] = value.strip
          end
        end
      end
      value_hash[:hls_version] = hls_version
      grab_next_line = true
    elsif ln =~ /^#EXT-X-MEDIA:/
      values = ln.split(':')[1]
      values = values.scan(/(?:\".*?\"|[^,])+/)
      unless values.empty?
        value_hash = Hash.new
        values.each do |kvpair|
          kv_split = kvpair.split('=')
          key = kv_split[0]
          value = kv_split[1]
          value = value.gsub("\"", "")
          value_hash[key] = value.strip
        end
        sub_manifest_name = value_hash['URI']
        split_arr = uri.split('/', -1)
        split_arr.delete_at(split_arr.size - 1)
        sub_manifest_url = split_arr.join('/') + '/' + sub_manifest_name
        value_hash[:manifest_url] = sub_manifest_url
        value_hash[:hls_version] = hls_version
        return_data << value_hash
        value_hash = Hash.new
      end
    elsif grab_next_line
      sub_manifest_hash = Hash.new
      sub_manifest_name = ln.chomp!
      split_arr = uri.split('/', -1)
      split_arr.delete_at(split_arr.size - 1)
      sub_manifest_url = split_arr.join('/') + '/' + sub_manifest_name
      value_hash[:manifest_url] = sub_manifest_url
      return_data << value_hash
      value_hash = Hash.new
      grab_next_line = false
    else
      ; # explicitly ignoring the rest..
    end
  end
  return return_data
end

def parse_hls_variant_manifest(response, uri, inspect_seg)
  reader = StringIO.new(response.body)
  return_hash = Hash.new
  grab_next_line = false
  media_sequence = nil
  reader.each_line do |ln|
    if ln =~ /^#EXT-X-KEY:/
      key_method = ln.scan(/(?:\".*?\"|[^:])+/).last.split("METHOD=").last.split(',').first
      return_hash[:key_method] = key_method
    elsif ln =~ /^#EXT-X-MEDIA-SEQUENCE:/
      media_sequence = ln.split(':').last.strip
    elsif ln =~ /^#EXTINF:/
      target_duration = ln.split(':').last
      return_hash[:target_duration] = target_duration.gsub(',','').strip
      grab_next_line = true
    elsif grab_next_line
      split_arr = uri.split('/', -1)
      split_arr.delete_at(split_arr.size - 1)
      if inspect_seg
        seg_info = inspect_segment(split_arr.join('/') + '/' + ln)
        return_hash.merge!(seg_info)
      end
      segment_syntax = ln.gsub(/\d+(?!\/).ts.*/, '')
      segment_syntax = split_arr.join('/') + '/' + segment_syntax.strip
      return_hash[:segment_syntax] = segment_syntax
      break
    end
  end
  return return_hash
end

def inspect_segment(seg_url)
  streaminfo = {}
  complete_seg_url = @cloudfront_url + seg_url
  puts "probe URL => #{complete_seg_url}"
  cmd = "ffprobe -v quiet -print_format json -show_format -show_streams '#{complete_seg_url.strip}'"
  puts "Command #{cmd}"
  cmd_res = `#{cmd}`
  mediainfo = JSON.parse(cmd_res)
  puts "Media info => #{mediainfo}"
  if !mediainfo.nil? && !mediainfo["streams"].nil?
    bandwidth = mediainfo["format"]["bit_rate"] if !mediainfo["format"].nil? && !mediainfo["format"]["bit_rate"].nil?
    mediainfo["streams"].each do | stream_info |
      if !stream_info["pix_fmt"].nil?
        resolution = stream_info["width"].to_s + "x" + stream_info["height"].to_s
        streaminfo = {
            BANDWIDTH: bandwidth,
            CODECS: stream_info["codec_name"],
            TYPE: 'VIDEO',
            RESOLUTION: resolution,
        }
        break
      end
    end
  end
  streaminfo
end

def get_elasticsearch_client
  @es_client ||= Elasticsearch::Client.new(
      {hosts: @servers, retry_on_failure: RETRY_ON_FAILURE, request_timeout: REQUEST_TIMEOUT, log: true, send_get_body_as: 'POST'})
end
