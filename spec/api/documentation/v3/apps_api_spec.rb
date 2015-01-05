require 'spec_helper'
require 'awesome_print'
require 'rspec_api_documentation/dsl'

resource 'Apps (Experimental)', type: :api do
  let(:user) { VCAP::CloudController::User.make }
  let(:user_header) { headers_for(user)['HTTP_AUTHORIZATION'] }
  header 'AUTHORIZATION', :user_header

  def do_request_with_error_handling
    do_request
    if response_status == 500
      error = MultiJson.load(response_body)
      ap error
      raise error['description']
    end
  end

  context 'standard endpoints' do
    get '/v3/apps/:guid' do
      let(:app_model) { VCAP::CloudController::AppModel.make(name: name) }
      let(:guid) { app_model.guid }
      let(:space_guid) { app_model.space_guid }
      let(:space) { VCAP::CloudController::Space.find(guid: space_guid) }
      let(:name) { 'my_app' }

      before do
        space.organization.add_user user
        space.add_developer user
      end

      example 'Get an App' do
        expected_response = {
          'name'   => name,
          'guid'   => guid,
          '_links' => {
            'self'      => { 'href' => "/v3/apps/#{guid}" },
            'processes' => { 'href' => "/v3/apps/#{guid}/processes" },
            'space'     => { 'href' => "/v2/spaces/#{space_guid}" },
          }
        }

        do_request_with_error_handling

        parsed_response = MultiJson.load(response_body)
        expect(response_status).to eq(200)
        expect(parsed_response).to match(expected_response)
      end
    end

    post '/v3/apps' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:space_guid) { space.guid }
      let(:name) { 'my_app' }

      before do
        space.organization.add_user(user)
        space.add_developer(user)
      end

      parameter :name, 'Name of the App', required: true
      parameter :space_guid, 'GUID of associated Space', required: true

      let(:raw_post) { MultiJson.dump(params, pretty: true) }

      example 'Create an App' do
        expect {
          do_request_with_error_handling
        }.to change { VCAP::CloudController::AppModel.count }.by(1)

        expected_guid = VCAP::CloudController::AppModel.last.guid
        expected_response = {
          'name'   => name,
          'guid'   => expected_guid,
          '_links' => {
            'self'      => { 'href' => "/v3/apps/#{expected_guid}" },
            'processes' => { 'href' => "/v3/apps/#{expected_guid}/processes" },
            'space'     => { 'href' => "/v2/spaces/#{space_guid}" },
          }
        }

        parsed_response = MultiJson.load(response_body)
        expect(response_status).to eq(201)
        expect(parsed_response).to match(expected_response)
      end
    end

    patch '/v3/apps/:guid' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:space_guid) { space.guid }
      let(:app_model) { VCAP::CloudController::AppModel.make(name: 'original_name', space_guid: space_guid) }

      before do
        space.organization.add_user(user)
        space.add_developer(user)
      end

      parameter :name, 'Name of the App'

      let(:name) { 'new_name' }
      let(:guid) { app_model.guid }

      let(:raw_post) { MultiJson.dump(params, pretty: true) }

      example 'Updating an App' do
        do_request_with_error_handling

        expected_response = {
          'name'   => name,
          'guid'   => app_model.guid,
          '_links' => {
            'self'      => { 'href' => "/v3/apps/#{app_model.guid}" },
            'processes' => { 'href' => "/v3/apps/#{app_model.guid}/processes" },
            'space'     => { 'href' => "/v2/spaces/#{space_guid}" },
          }
        }

        parsed_response = MultiJson.load(response_body)
        expect(response_status).to eq(200)
        expect(parsed_response).to match(expected_response)
      end
    end

    delete '/v3/apps/:guid' do
      let!(:app_model) { VCAP::CloudController::AppModel.make }
      let(:guid) { app_model.guid }
      let(:space_guid) { app_model.space_guid }
      let(:space) { VCAP::CloudController::Space.find(guid: space_guid) }

      before do
        space.organization.add_user(user)
        space.add_developer(user)
      end

      example 'Delete an App' do
        expect {
          do_request_with_error_handling
        }.to change { VCAP::CloudController::AppModel.count }.by(-1)
        expect(response_status).to eq(204)
      end
    end
  end

  context 'nested endpoints' do
    put '/v3/apps/:guid/processes' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:stack) { VCAP::CloudController::Stack.make }

      parameter :process_guid, 'GUID of process', required: true

      let!(:process) { VCAP::CloudController::AppFactory.make(space_guid: space.guid) }
      let(:process_guid) { process.guid }

      let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }
      let(:guid) { app_model.guid }

      let(:raw_post) { MultiJson.dump(params, pretty: true) }

      before do
        space.organization.add_user(user)
        space.add_developer(user)
      end

      example 'Add a Process' do
        expect {
          do_request_with_error_handling
        }.not_to change { VCAP::CloudController::App.count }

        expect(response_status).to eq(204)
        expect(app_model.reload.processes.first).to eq(process.reload)
      end
    end

    get '/v3/apps/:guid/processes' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:stack) { VCAP::CloudController::Stack.make }

      parameter :process_guid, 'GUID of process', required: true

      let!(:process) { VCAP::CloudController::AppFactory.make(space_guid: space.guid) }
      let(:process_guid) { process.guid }
      let(:process_type) { process.type }

      let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }
      let(:guid) { app_model.guid }

      before do
        space.organization.add_user(user)
        space.add_developer(user)
        app_model.add_process_by_guid(process_guid)
      end

      example 'List associated processes' do
        expected_response = [
          {
            'guid' => process_guid,
            'type' => process_type,
          }
        ]
        do_request_with_error_handling

        parsed_response = MultiJson.load(response_body)

        expect(response_status).to eq(200)
        expect(parsed_response).to match(expected_response)
      end
    end

    delete '/v3/apps/:guid/processes' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:stack) { VCAP::CloudController::Stack.make }

      parameter :process_guid, 'GUID of process', required: true

      let!(:process) { VCAP::CloudController::AppFactory.make(space_guid: space.guid) }
      let(:process_guid) { process.guid }

      let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }
      let(:guid) { app_model.guid }

      let(:raw_post) { MultiJson.dump(params, pretty: true) }

      before do
        space.organization.add_user(user)
        space.add_developer(user)

        app_model.add_process_by_guid(process_guid)
      end

      example 'Remove a Process' do
        expect {
          do_request_with_error_handling
        }.not_to change { VCAP::CloudController::App.count }

        expect(response_status).to eq(204)
        expect(app_model.reload.processes).to eq([])
      end
    end
  end
end
