require 'spec_helper'

module VCAP::CloudController
  module Dea
    describe Stager do
      let(:config) do
        instance_double(Config)
      end

      let(:message_bus) do
        instance_double(CfMessageBus::MessageBus, publish: nil)
      end

      let(:dea_pool) do
        instance_double(Dea::Pool)
      end

      let(:stager_pool) do
        instance_double(Dea::StagerPool)
      end

      let(:runners) do
        instance_double(Runners)
      end

      let(:app) do
        AppFactory.make
      end

      let(:runner) { double(:Runner) }

      subject(:stager) do
        Stager.new(app, config, message_bus, dea_pool, stager_pool, runners)
      end

      describe '#stage' do
        let(:stager_task) do
          double(AppStagerTask)
        end

        let(:reply_json_error) { nil }
        let(:reply_error_info) { nil }
        let(:detected_buildpack) { nil }
        let(:detected_start_command) { 'wait_for_godot' }
        let(:buildpack_key) { nil }
        let(:reply_json) do
          {
            'task_id' => 'task-id',
            'task_log' => 'task-log',
            'task_streaming_log_url' => nil,
            'detected_buildpack' => detected_buildpack,
            'buildpack_key' => buildpack_key,
            'detected_start_command' => detected_start_command,
            'error' => reply_json_error,
            'error_info' => reply_error_info,
            'droplet_sha1' => 'droplet-sha1'
          }
        end
        let(:staging_result) do
          AppStagerTask::Response.new(reply_json)
        end

        before do
          allow(AppStagerTask).to receive(:new).and_return(stager_task)
          allow(stager_task).to receive(:stage).and_yield(staging_result).and_return('fake-stager-response')
          allow(runners).to receive(:runner_for_app).with(app).and_return(runner)
          allow(runner).to receive(:start).with('fake-staging-result')
          allow(dea_pool).to receive(:mark_app_started).with()

         stager.stage
        end

        it 'stages the app with a stager task' do
          expect(stager_task).to have_received(:stage)
          expect(AppStagerTask).to have_received(:new).with(config,
                                                            message_bus,
                                                            app,
                                                            dea_pool,
                                                            stager_pool,
                                                            an_instance_of(CloudController::Blobstore::UrlGenerator))
        end

        it 'starts the app with the returned staging result' do
          expect(runner).to have_received(:start).with('fake-staging-result')
        end

        it 'records the stager response on the app' do
          expect(app.last_stager_response).to eq('fake-stager-response')
        end

        context 'staging block' do
          context 'when app staging succeeds' do
            let(:detected_buildpack) { 'buildpack detect output' }

            context 'when no other staging has happened' do
              before do
                allow(dea_pool).to receive(:mark_app_started)
              end

              it 'marks the app as staged' do
                expect { stage }.to change { app.refresh.staged? }.to(true)
              end

              it 'saves the detected buildpack' do
                expect { stage }.to change { app.refresh.detected_buildpack }.from(nil)
              end

              context 'and the droplet has been uploaded' do
                it 'saves the detected start command' do
                  app.droplet_hash = 'Abc'
                  expect { stage }.to change {
                    app.current_droplet.refresh
                    app.detected_start_command
                  }.from('').to('wait_for_godot')
                end
              end

              context 'when the droplet somehow has not been uploaded (defensive)' do
                it 'does not change the start command' do
                  expect { stage }.not_to change {
                    app.detected_start_command
                  }.from('')
                end
              end

              context 'when detected_start_command is not returned' do
                let(:reply_json) do
                  {
                    'task_id' => 'task-id',
                    'task_log' => 'task-log',
                    'task_streaming_log_url' => nil,
                    'detected_buildpack' => detected_buildpack,
                    'buildpack_key' => buildpack_key,
                    'error' => reply_json_error,
                    'error_info' => reply_error_info,
                    'droplet_sha1' => 'droplet-sha1'
                  }
                end

                it 'does not change the detected start command' do
                  app.droplet_hash = 'Abc'
                  expect { stage }.not_to change {
                    app.current_droplet.refresh
                    app.detected_start_command
                  }.from('')
                end
              end

              context 'when an admin buildpack is used' do
                let(:admin_buildpack) { Buildpack.make(name: 'buildpack-name') }
                let(:buildpack_key) { admin_buildpack.key }
                before do
                  app.buildpack = admin_buildpack.name
                end

                it 'saves the detected buildpack guid' do
                  expect { stage }.to change { app.refresh.detected_buildpack_guid }.from(nil)
                end
              end

              it 'does not clobber other attributes that changed between staging' do
                # fake out the app refresh as the race happens after it
                allow(app).to receive(:refresh)

                other_app_ref = App.find(guid: app.guid)
                other_app_ref.command = 'some other command'
                other_app_ref.save

                expect { stage }.to_not change {
                  other_app_ref.refresh.command
                }
              end
            end
          end
        end
      end
    end
  end
end
