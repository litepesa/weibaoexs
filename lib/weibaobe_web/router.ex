defmodule WeibaobeWeb.Router do
  use WeibaobeWeb, :router

  alias WeibaobeWeb.Plugs

  # API pipelines
  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug
  end

  pipeline :api_auth do
    plug :accepts, ["json"]
    plug CORSPlug
    plug Plugs.Auth
    plug Plugs.RequireAuth
  end

  pipeline :api_admin do
    plug :accepts, ["json"]
    plug CORSPlug
    plug Plugs.Auth
    plug Plugs.RequireAuth
    plug Plugs.RequireAdmin
  end

  pipeline :api_optional_auth do
    plug :accepts, ["json"]
    plug CORSPlug
    plug Plugs.LoadCurrentUser
  end

  # Health check
  get "/health", WeibaobeWeb.HealthController, :health

  # API routes
  scope "/api/v1", WeibaobeWeb do
    # ===============================
    # AUTH ROUTES (FIXED - Resolves Chicken-and-Egg Problem)
    # ===============================
    scope "/auth" do
      pipe_through :api

      # 🔧 CRITICAL FIX: User sync endpoint WITHOUT authentication middleware
      post "/sync", AuthController, :sync_user
      post "/verify", AuthController, :verify_token
    end

    # Protected auth routes
    scope "/auth" do
      pipe_through :api_auth

      get "/user", AuthController, :get_current_user
      post "/profile-sync", AuthController, :sync_user_with_token
    end

    # ===============================
    # PUBLIC ROUTES (NO AUTH REQUIRED)
    # ===============================
    scope "" do
      pipe_through :api_optional_auth

      # Video discovery endpoints
      get "/videos", VideoController, :index
      get "/videos/featured", VideoController, :featured
      get "/videos/trending", VideoController, :trending
      get "/videos/:videoId", VideoController, :show
      post "/videos/:videoId/views", VideoController, :increment_views
      get "/users/:userId/videos", VideoController, :user_videos

      # Comment endpoints
      get "/videos/:videoId/comments", CommentController, :index

      # User profile endpoints
      get "/users/:userId", UserController, :show
      get "/users/:userId/stats", UserController, :stats
      get "/users/:userId/followers", SocialController, :get_followers
      get "/users/:userId/following", SocialController, :get_following

      # User search
      get "/users", UserController, :index
      get "/users/search", UserController, :search

      # Social discovery
      get "/social/discover", SocialController, :get_discover_users
      get "/social/users/:userId/stats", SocialController, :get_user_social_stats
    end

    # ===============================
    # PROTECTED ROUTES (FIREBASE AUTH + USER EXISTS IN DB)
    # ===============================
    scope "" do
      pipe_through :api_auth

      # User management
      put "/users/:userId", UserController, :update
      delete "/users/:userId", UserController, :delete

      # Video creation and management
      post "/videos", VideoController, :create
      put "/videos/:videoId", VideoController, :update
      delete "/videos/:videoId", VideoController, :delete

      # Video interactions
      post "/videos/:videoId/like", VideoController, :like_video
      delete "/videos/:videoId/like", VideoController, :unlike_video
      post "/videos/:videoId/share", VideoController, :share_video
      get "/users/:userId/liked-videos", VideoController, :user_liked_videos

      # Social features
      post "/users/:userId/follow", SocialController, :follow_user
      delete "/users/:userId/follow", SocialController, :unfollow_user
      get "/feed/following", VideoController, :following_feed
      get "/social/suggested", SocialController, :get_suggested_users
      get "/social/activity", SocialController, :get_follow_activity
      post "/social/bulk-check", SocialController, :bulk_check_following

      # Comment management
      post "/videos/:videoId/comments", CommentController, :create
      delete "/comments/:commentId", CommentController, :delete
      post "/comments/:commentId/like", CommentController, :like
      delete "/comments/:commentId/like", CommentController, :unlike

      # User analytics
      get "/stats/videos", VideoController, :video_stats

      # Wallet endpoints
      get "/wallet/:userId", WalletController, :show
      get "/wallet/:userId/transactions", WalletController, :transactions
      post "/wallet/:userId/purchase-request", WalletController, :create_purchase_request

      # File upload endpoints
      post "/upload", UploadController, :upload_file
      post "/upload/batch", UploadController, :batch_upload
      get "/upload/health", UploadController, :health_check
    end

    # ===============================
    # ADMIN ROUTES (ADMIN ACCESS REQUIRED)
    # ===============================
    scope "/admin" do
      pipe_through :api_admin

      # Video moderation
      post "/videos/:videoId/featured", VideoController, :toggle_featured
      post "/videos/:videoId/active", VideoController, :toggle_active

      # User management
      post "/users/:userId/status", UserController, :update_status

      # Wallet management
      post "/wallet/:userId/add-coins", WalletController, :add_coins
      get "/purchase-requests", WalletController, :pending_purchases
      post "/purchase-requests/:requestId/approve", WalletController, :approve_purchase
      post "/purchase-requests/:requestId/reject", WalletController, :reject_purchase

      # Analytics
      get "/stats/network", SocialController, :get_network_stats
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:weibaobe, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: WeibaobeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
