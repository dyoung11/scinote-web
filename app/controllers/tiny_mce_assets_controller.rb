# frozen_string_literal: true

class TinyMceAssetsController < ApplicationController
  before_action :load_vars, only: %i(marvinjs_show marvinjs_update)

  before_action :check_read_permission, only: %i(marvinjs_show marvinjs_update)
  before_action :check_edit_permission, only: %i(marvinjs_update)

  def create
    image = params.fetch(:file) { render_404 }
    tiny_img = TinyMceAsset.new(team_id: current_team.id, saved: false)

    tiny_img.transaction do
      tiny_img.save!
      tiny_img.image.attach(io: image, filename: image.original_filename)
    end

    if tiny_img.persisted?
      render json: {
        image: {
          url: url_for(tiny_img.image),
          token: Base62.encode(tiny_img.id)
        }
      }, content_type: 'text/html'
    else
      render json: {
        error: tiny_img.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def download
    asset = current_team.tiny_mce_assets.find_by_id(Base62.decode(params[:id]))
    if asset&.image&.attached?
      redirect_to rails_blob_path(asset.image, disposition: 'attachment')
    else
      render_404
    end
  end

  def marvinjs_show
    asset = current_team.tiny_mce_assets.find_by_id(params[:id])
    return render_404 unless asset

    render json: {
      name: asset.image.metadata[:name],
      description: asset.image.metadata[:description]
    }
  end

  def marvinjs_create
    result = MarvinJsService.create_sketch(marvin_params, current_user)
    if result[:asset]
      render json: {
        image: {
          url: rails_representation_url(result[:asset].preview),
          token: Base62.encode(result[:asset].id),
          source_id: result[:asset].id,
          source_type: result[:asset].image.metadata[:asset_type]
        }
      }, content_type: 'text/html'
    else
      render json: result[:asset].errors, status: :unprocessable_entity
    end
  end

  def marvinjs_update
    asset = MarvinJsService.update_sketch(marvin_params, current_user)
    if asset
      render json: { url: rails_representation_url(asset.preview), id: asset.id }
    else
      render json: { error: t('marvinjs.no_sketches_found') }, status: :unprocessable_entity
    end
  end

  private

  def load_vars
    @asset = current_team.tiny_mce_assets.find_by_id(params[:id])
    return render_404 unless @asset

    @assoc ||= @asset.object

    if @assoc.class == Step
      @protocol = @assoc.protocol
    elsif @assoc.class == Protocol
      @protocol = @assoc
    elsif @assoc.class == MyModule
      @my_module = @assoc
    elsif @assoc.class == Result
      @my_module = @assoc.my_module
    end
  end

  def check_read_permission
    if @assoc.class == Step || @assoc.class == Protocol
      render_403 && return unless can_read_protocol_in_module?(@protocol) ||
                                  can_read_protocol_in_repository?(@protocol)
    elsif @assoc.class == Result || @assoc.class == MyModule
      render_403 and return unless can_read_experiment?(@my_module.experiment)
    end
  end

  def check_edit_permission
    if @assoc.class == Step || @assoc.class == Protocol
      render_403 && return unless can_manage_protocol_in_module?(@protocol) ||
                                  can_manage_protocol_in_repository?(@protocol)
    elsif @assoc.class == Result || @assoc.class == MyModule
      render_403 and return unless can_manage_module?(@my_module)
    end
  end

  def marvin_params
    params.permit(:id, :description, :object_id, :object_type, :name, :image)
  end
end
