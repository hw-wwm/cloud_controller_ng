module VCAP::CloudController
  module Dea
    class Stager
      EXPORT_ATTRIBUTES = [
        :instances,
        :state,
        :memory,
        :package_state,
        :version
      ]

      def initialize(app, config, message_bus, dea_pool, stager_pool, runners)
        @app = app
        @config = config
        @message_bus = message_bus
        @dea_pool = dea_pool
        @stager_pool = stager_pool
        @runners = runners
      end

      def stage_package
        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
        task = AppStagerTask.new(@config, @message_bus, @app, @dea_pool, @stager_pool, blobstore_url_generator)
        last_stager_response = task.stage
      end

      def stage
        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
        task = AppStagerTask.new(@config, @message_bus, @app, @dea_pool, @stager_pool, blobstore_url_generator)

        @app.last_staging_result = task.stage do |staging_result|
          instance_was_started_by_dea = !!staging_result.droplet_hash
          @app.db.transaction do
            @app.lock!
            @app.mark_as_staged
            @app.update_detected_buildpack(staging_result.detected_buildpack, staging_result.buildpack_key)
            @app.current_droplet.update_detected_start_command(staging_result.detected_start_command) if @app.current_droplet
          end

          @runners.runner_for_app(@app)
            .start(started_instances: instance_was_started_by_dea ? 1 : 0)
        end
      end

      def staging_complete(_)
        raise NotImplementedError
      end
    end
  end
end
