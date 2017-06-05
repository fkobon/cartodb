require 'json'

# Version History
# 1.0.0: export user metadata
module Carto
  module UserMetadataExportServiceConfiguration
    CURRENT_VERSION = '1.0.0'.freeze
    EXPORTED_USER_ATTRIBUTES = [
      :email, :crypted_password, :salt, :database_name, :username, :admin, :enabled, :invite_token, :invite_token_date,
      :map_enabled, :quota_in_bytes, :table_quota, :account_type, :private_tables_enabled, :period_end_date,
      :map_view_quota, :max_layers, :database_timeout, :user_timeout, :upgraded_at, :map_view_block_price,
      :geocoding_quota, :dashboard_viewed_at, :sync_tables_enabled, :database_host, :geocoding_block_price, :api_key,
      :notification, :organization_id, :created_at, :updated_at, :disqus_shortname, :id, :twitter_username, :website,
      :description, :name, :avatar_url, :database_schema, :soft_geocoding_limit, :auth_token,
      :twitter_datasource_enabled, :twitter_datasource_block_price, :twitter_datasource_block_size,
      :twitter_datasource_quota, :soft_twitter_datasource_limit, :available_for_hire, :private_maps_enabled,
      :google_sign_in, :last_password_change_date, :max_import_file_size, :max_import_table_row_count,
      :max_concurrent_import_count, :last_common_data_update_date, :google_maps_key, :google_maps_private_key,
      :enable_account_token, :location, :here_isolines_quota, :here_isolines_block_price, :soft_here_isolines_limit,
      :obs_snapshot_quota, :obs_snapshot_block_price, :soft_obs_snapshot_limit, :mobile_xamarin,
      :mobile_custom_watermark, :mobile_offline_maps, :mobile_gis_extension, :mobile_max_open_users,
      :mobile_max_private_users, :obs_general_quota, :obs_general_block_price, :soft_obs_general_limit, :viewer,
      :salesforce_datasource_enabled, :builder_enabled, :geocoder_provider, :isolines_provider, :routing_provider,
      :github_user_id, :engine_enabled, :mapzen_routing_quota, :mapzen_routing_block_price, :soft_mapzen_routing_limit,
      :no_map_logo, :org_admin, :last_name
    ].freeze

    def compatible_version?(version)
      version.to_i == CURRENT_VERSION.split('.')[0].to_i
    end
  end

  module UserMetadataExportServiceImporter
    include UserMetadataExportServiceConfiguration

    def build_user_from_json_export(exported_json_string)
      build_user_from_hash_export(JSON.parse(exported_json_string).deep_symbolize_keys)
    end

    def build_user_from_hash_export(exported_hash)
      raise 'Wrong export version' unless compatible_version?(exported_hash[:version])

      build_user_from_hash(exported_hash[:user])
    end

    private

    def build_user_from_hash(exported_user)
      user = User.new(exported_user.slice(*EXPORTED_USER_ATTRIBUTES))

      user.feature_flags_user = exported_user[:feature_flags].map { |ff_name| build_feature_flag_from_name(ff_name) }
                                                             .compact

      user.assets = exported_user[:assets].map { |asset| build_asset_from_hash(asset) }

      user.layers = exported_user[:layers].map.with_index { |layer, i| build_layer_from_hash(layer, order: i) }

      # Must be the last one to avoid attribute assignments to try to run SQL
      user.id = exported_user[:id]
      user
    end

    def build_feature_flag_from_name(ff_name)
      ff = FeatureFlag.where(name: ff_name).first
      if ff
        FeatureFlagsUser.new(feature_flag_id: ff.id)
      else
        CartoDB::Logger.warning(message: 'Feature flag not found in user import', feature_flag: ff_name)
        nil
      end
    end

    def build_asset_from_hash(exported_asset)
      Asset.new(
        public_url: exported_asset[:public_url],
        kind: exported_asset[:kind],
        storage_info: exported_asset[:storage_info]
      )
    end

    def build_layer_from_hash(exported_layer, order:)
      Layer.new(
        options: exported_layer[:options],
        kind: exported_layer[:kind],
        order: order
      )
    end
  end

  module UserMetadataExportServiceExporter
    include UserMetadataExportServiceConfiguration

    def export_user_json_string(user_id)
      export_user_json_hash(user_id).to_json
    end

    def export_user_json_hash(user_id)
      {
        version: CURRENT_VERSION,
        user: export(User.find(user_id))
      }
    end

    private

    def export(user)
      user_hash = EXPORTED_USER_ATTRIBUTES.map { |att| [att, user.send(att)] }.to_h

      user_hash[:feature_flags] = user.feature_flags_user.map(&:feature_flag).map(&:name)

      user_hash[:assets] = user.assets.map { |a| export_asset(a) }

      user_hash[:layers] = user.layers.map { |l| export_layer(l) }

      vis_exporter = VisualizationsExportService2.new

      user_hash[:visualizations] = user.visualizations.map do |vis|
        vis_exporter.export_visualization_json_hash(vis, user, full_export: true)
      end

      # Visualizations
        # datasets
        # permissions
        # id
        # mapcap

      # Notifications ?

      # Imports, syncs?

      user_hash
    end

    def export_asset(asset)
      {
        public_url: asset.public_url,
        kind: asset.kind,
        storage_info: asset.storage_info
      }
    end

    def export_layer(layer)
      # Only custom basemap layers, many fields are unused
      {
        options: layer.options,
        kind: layer.kind
      }
    end
  end

  # Both String and Hash versions are provided because `deep_symbolize_keys` won't symbolize through arrays
  # and having separated methods make handling and testing much easier.
  class UserMetadataExportService
    include UserMetadataExportServiceImporter
    include UserMetadataExportServiceExporter
  end
end