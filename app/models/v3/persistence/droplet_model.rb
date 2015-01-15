module VCAP::CloudController
  class DropletModel < Sequel::Model(:v3_droplets)
    PENDING_STATE = 'PENDING'
    STAGING_STATE = 'STAGING'
    FAILED_STATE  = 'FAILED'
    STAGED_STATE  = 'STAGED'
    DROPLET_STATES = [STAGED_STATE, PENDING_STATE, STAGING_STATE, FAILED_STATE].map(&:freeze).freeze

    def validate
      validates_includes DROPLET_STATES, :state, allow_missing: true
    end
  end
end
