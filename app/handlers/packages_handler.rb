module VCAP::CloudController
  class PackageUploadMessage
    attr_reader :package_path, :package_guid

    def initialize(package_guid, opts)
      @package_guid = package_guid
      @package_path = opts['bits_path']
    end

    def validate
      return false, 'An application zip file must be uploaded.' unless @package_path
      true
    end
  end

  class PackageStagingMessage
    attr_reader :droplet_guid, :package_guid

    def initialize(package_guid, droplet_guid)
      @package_guid = package_guid
      @droplet_guid = droplet_guid
    end

    def validate
      return false, 'A droplet guid must be given.' unless @droplet_guid
      true
    end
  end

  class PackageCreateMessage
    attr_reader :space_guid, :type, :url
    attr_accessor :error

    def self.create_from_http_request(space_guid, body)
      opts = body && MultiJson.load(body)
      raise MultiJson::ParseError.new('invalid request body') unless opts.is_a?(Hash)
      PackageCreateMessage.new(space_guid, opts)
    rescue MultiJson::ParseError => e
      message = PackageCreateMessage.new(space_guid, {})
      message.error = e.message
      message
    end

    def initialize(space_guid, opts)
      @space_guid = space_guid
      @type     = opts['type']
      @url      = opts['url']
    end

    def validate
      return false, [error] if error
      errors = []
      errors << validate_type_field
      errors << validate_url
      errs = errors.compact
      [errs.length == 0, errs]
    end

    private

    def validate_type_field
      return 'The type field is required' if @type.nil?
      valid_type_fields = %w(bits docker)

      if !valid_type_fields.include?(@type)
        return "The type field needs to be one of '#{valid_type_fields.join(', ')}'"
      end
      nil
    end

    def validate_url
      return 'The url field cannot be provided when type is bits.' if @type == 'bits' && !@url.nil?
      return 'The url field must be provided for type docker.' if @type == 'docker' && @url.nil?
      nil
    end
  end

  class PackagesHandler
    class Unauthorized < StandardError; end
    class InvalidPackageType < StandardError; end
    class InvalidPackage < StandardError; end
    class SpaceNotFound < StandardError; end
    class PackageNotFound < StandardError; end
    class BitsAlreadyUploaded < StandardError; end

    def initialize(config, stagers)
      @config = config
      @stagers = stagers
    end

    def create(message, access_context)
      package          = PackageModel.new
      package.space_guid = message.space_guid
      package.type     = message.type
      package.url      = message.url
      package.state = message.type == 'bits' ? PackageModel::CREATED_STATE : PackageModel::READY_STATE

      space = Space.find(guid: package.space_guid)
      raise SpaceNotFound if space.nil?

      raise Unauthorized if access_context.cannot?(:create, package, space)
      package.save

      package
    rescue Sequel::ValidationFailed => e
      raise InvalidPackage.new(e.message)
    end

    def upload(message, access_context)
      package = PackageModel.find(guid: message.package_guid)

      raise PackageNotFound if package.nil?
      raise InvalidPackageType.new('Package type must be bits.') if package.type != 'bits'
      raise BitsAlreadyUploaded.new('Bits may be uploaded only once. Create a new package to upload different bits.') if package.state != PackageModel::CREATED_STATE

      space = Space.find(guid: package.space_guid)
      raise SpaceNotFound if space.nil?

      raise Unauthorized if access_context.cannot?(:create, package, space)

      package.update(state: PackageModel::PENDING_STATE)

      bits_upload_job = Jobs::Runtime::PackageBits.new(package.guid, message.package_path)
      Jobs::Enqueuer.new(bits_upload_job, queue: Jobs::LocalQueue.new(@config)).enqueue

      package
    end

    def delete(guid, access_context)
      package = PackageModel.find(guid: guid)
      return nil if package.nil?

      space = Space.find(guid: package.space_guid)

      package.db.transaction do
        package.lock!
        raise Unauthorized if access_context.cannot?(:delete, package, space)
        package.destroy
      end

      blobstore_delete = Jobs::Runtime::BlobstoreDelete.new(package.guid, :package_blobstore, nil)
      Jobs::Enqueuer.new(blobstore_delete, queue: 'cc-generic').enqueue

      package
    end

    def show(guid, access_context)
      package = PackageModel.find(guid: guid)
      return nil if package.nil?
      raise Unauthorized if access_context.cannot?(:read, package)
      package
    end

    def stage(message, access_context)
      package = PackageModel.find(guid: message.package_guid)
      droplet = DropletModel.find(guid: message.droplet_guid)
      # return nil if droplet.nil?
      # raise Unauthorized if access_context.cannot?(:read, droplet)
      # return nil if package.nil?
      # raise Unauthorized if access_context.cannot?(:read, package)

      #whatever
      app = AppFromPackageAdapter.new(package, droplet)
      @stagers.dea_stager(app).stage_package
    end
  end

  class AppFromPackageAdapter
    class Stacky
      def name
        'lucid64'
      end
    end
    def initialize(package, droplet)
      @package = package
      @droplet = droplet
    end

    def db
      @droplet.db
    end

    def mark_as_staged
      @droplet.update(state: DropletModel::STAGED_STATE)
    end

    def update_detected_buildpack(output, key)
    end

    def lock!
      @droplet.lock!
    end

    def current_droplet
      nil
    end

    def update(opts)
      @staging_task_id = opts[:staging_task_id]
    end

    def guid
      @package.guid
    end

    def space
      Space.find(guid: @package.space_guid)
    end

    def refresh
      @package.refresh
    end

    def file_descriptors
      1024
    end

    def memory
      1024
    end

    def disk_quota
      -1 #why?
    end

    def environment_json
      nil
    end

    def staging_task_id
      @staging_task_id
    end

    def staging_failed?
      false
    end

    def service_bindings
      {}
    end

    def stack
      Stacky.new
    end

    def metadata
      nil
    end

    def buildpack
      AutoDetectionBuildpack.new
    end

    def name
      guid
    end

    def uris
      nil
    end

    def production
      nil
    end

    def droplet_hash
      nil
    end

    def current_droplet
      nil
    end

    def version
      nil
    end

    def console
      nil
    end

    def debug
      nil
    end

    def command
      nil
    end

    def health_check_timeout
      60
    end

    def vcap_application
      nil
    end
  end
end
