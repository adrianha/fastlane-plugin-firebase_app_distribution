require 'googleauth'
require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")
  module Auth
    module FirebaseAppDistributionAuthClient
      TOKEN_CREDENTIAL_URI = "https://oauth2.googleapis.com/token"
      REDACTION_EXPOSED_LENGTH = 5
      REDACTION_CHARACTER = "X"
      SCOPE = "https://www.googleapis.com/auth/cloud-platform"

      # In this type of application, the client secret is not treated as a secret.
      # See: https://developers.google.com/identity/protocols/OAuth2InstalledApp
      CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
      CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi"

      # Returns an authorization object for any of the auth methods (Firebase CLI token,
      # Application Default Credentials, firebase-tools). To ensure that a specific
      # auth method is used, unset all other auth variables/parameters to nil/empty
      #
      # args
      #   google_service_path - Absolute path to the Google service account file
      #   firebase_cli_token - Refresh token
      #   debug - Whether to enable debug-level logging
      #
      # env variables
      #   FIREBASE_TOKEN - see firebase_cli_token
      #
      # Crashes if given invalid or missing credentials
      def get_authorization(google_service_path, firebase_cli_token, debug = false)
        if !google_service_path.nil? && !google_service_path.empty?
          UI.message("🔐 Authenticating with --service_credentials_file path parameter: #{google_service_path}")
          service_account(google_service_path, debug)
        elsif !firebase_cli_token.nil? && !firebase_cli_token.empty?
          UI.message("🔐 Authenticating with --firebase_cli_token parameter")
          firebase_token(firebase_cli_token, debug)
        elsif !ENV["FIREBASE_TOKEN"].nil? && !ENV["FIREBASE_TOKEN"].empty?
          UI.message("🔐 Authenticating with FIREBASE_TOKEN environment variable")
          firebase_token(ENV["FIREBASE_TOKEN"], debug)
        # TODO(lkellogg): Not using Google::Auth.get_application_default yet while we are still
        # using the old client for uploads. ADC also does not work for the get_udids action:
        # https://cloud.google.com/docs/authentication/troubleshoot-adc#user-creds-client-based
        # For now go back to just using the environment variable:
        elsif !ENV["GOOGLE_APPLICATION_CREDENTIALS"].nil? && !ENV["GOOGLE_APPLICATION_CREDENTIALS"].empty?
          UI.message("🔐 Authenticating with GOOGLE_APPLICATION_CREDENTIALS environment variable: #{ENV['GOOGLE_APPLICATION_CREDENTIALS']}")
          service_account(ENV["GOOGLE_APPLICATION_CREDENTIALS"], debug)
        elsif (refresh_token = refresh_token_from_firebase_tools)
          UI.message("🔐 No authentication method found. Using cached Firebase CLI credentials.")
          firebase_token(refresh_token, debug)
        else
          UI.user_error!(ErrorMessage::MISSING_CREDENTIALS)
          nil
        end
      end

      private

      def refresh_token_from_firebase_tools
        config_path = format_config_path
        if File.exist?(config_path)
          begin
            firebase_tools_tokens = JSON.parse(File.read(config_path))['tokens']
            return if firebase_tools_tokens.nil?
            refresh_token = firebase_tools_tokens['refresh_token']
          rescue JSON::ParserError
            UI.user_error!(ErrorMessage::PARSE_FIREBASE_TOOLS_JSON_ERROR)
          end
          refresh_token unless refresh_token.nil? || refresh_token.empty?
        end
      end

      def format_config_path
        if ENV["XDG_CONFIG_HOME"].nil? || ENV["XDG_CONFIG_HOME"].empty?
          File.expand_path(".config/configstore/firebase-tools.json", "~")
        else
          File.expand_path("configstore/firebase-tools.json", ENV["XDG_CONFIG_HOME"])
        end
      end

      def firebase_token(refresh_token, debug)
        client = Signet::OAuth2::Client.new(
          token_credential_uri: TOKEN_CREDENTIAL_URI,
          client_id: CLIENT_ID,
          client_secret: CLIENT_SECRET,
          refresh_token: refresh_token
        )
        client.fetch_access_token!
        client
      rescue Signet::AuthorizationError => error
        error_message = ErrorMessage::REFRESH_TOKEN_ERROR
        if debug
          error_message += "\nRefresh token used: #{format_token(refresh_token)}\n"
          error_message += error_details(error)
        else
          error_message += " #{debug_instructions}"
        end
        UI.user_error!(error_message)
      end

      def service_account(google_service_path, debug)
        # check if it's an external account or service account
        json_file = JSON.parse(File.read(google_service_path))
        auth = json_file["type"] == "external_account" ? Google::Auth::ExternalAccount::Credentials : Google::Auth::ServiceAccountCredentials
        service_account_credentials = auth.make_creds(
          json_key_io: File.open(google_service_path),
          scope: SCOPE
        )
        service_account_credentials.fetch_access_token!
        service_account_credentials
      rescue Errno::ENOENT
        UI.user_error!("#{ErrorMessage::SERVICE_CREDENTIALS_NOT_FOUND}: #{google_service_path}")
      rescue Signet::AuthorizationError => error
        error_message = "#{ErrorMessage::SERVICE_CREDENTIALS_ERROR}: \"#{google_service_path}\""
        if debug
          error_message += "\n#{error_details(error)}"
        else
          error_message += ". #{debug_instructions}"
        end
        UI.user_error!(error_message)
      end

      def error_details(error)
        "#{error.message}\nResponse status: #{error.response.status}"
      end

      def debug_instructions
        "For more information, try again with firebase_app_distribution's \"debug\" parameter set to \"true\"."
      end

      # Formats and redacts a token for printing out during debug logging. Examples:
      #   'abcd' -> '"abcd"''
      #   'abcdef1234' -> '"XXXXXf1234" (redacted)'
      def format_token(str)
        redaction_notice = str.length > REDACTION_EXPOSED_LENGTH ? " (redacted)" : ""
        exposed_start_char = [str.length - REDACTION_EXPOSED_LENGTH, 0].max
        exposed_characters = str[exposed_start_char, REDACTION_EXPOSED_LENGTH]
        redacted_characters = REDACTION_CHARACTER * [str.length - REDACTION_EXPOSED_LENGTH, 0].max
        "\"#{redacted_characters}#{exposed_characters}\"#{redaction_notice}"
      end
    end
  end
end
