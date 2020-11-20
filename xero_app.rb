# This is an example app that provides a dashboard to make some example
# calls to the Xero API actions after authorising the app via OAuth 2.0.

require 'sinatra'
require 'sinatra/reloader' if development?
require 'xero-ruby'
require 'securerandom'
require 'dotenv/load'
require 'jwt'
require 'pp'

set :session_secret, "328479283uf923fu8932fu923uf9832f23f232"
use Rack::Session::Pool
set :haml, :format => :html5

# Setup the credentials we use to connect to the XeroAPI
CREDENTIALS = {
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET'],
  redirect_uri: ENV['REDIRECT_URI'],
  scopes: ENV['SCOPES']
}

# We initialise an instance of the Xero API Client here so we can make calls
# to the API later. Memoization `||=`` will return a previously initialized client.
helpers do
  def xero_client
    @xero_client ||= XeroRuby::ApiClient.new(credentials: CREDENTIALS)
  end
end

get '/' do
  @form_data = {
    given_name: '',
    family_name: '',
    email: '',
    org_name: '',
    contacts_count: 0
  }
  @auth_url = xero_client.authorization_url
  haml :home
end

get '/callback' do
  token_set = xero_client.get_token_set_from_callback(params)
  @id_token_details = JWT.decode(token_set['id_token'], nil, false)[0]
  puts "\n"
  puts @id_token_details

  tenant_id = xero_client.connections.sort { |a,b|
    DateTime.parse(a['updatedDateUtc']) <=> DateTime.parse(b['updatedDateUtc'])
  }.first['tenantId']

  @organisation = xero_client.accounting_api.get_organisations(tenant_id).organisations[0]
  
  @contacts = []
  page = 1
  continue = true
  while continue
    opts = { page: page }
    puts opts
    contacts = xero_client.accounting_api.get_contacts(tenant_id, opts).contacts

    if contacts.count > 0 
      @contacts << contacts
      page += 1
    else
      continue = false
    end
  end

  puts @organisation.inspect

  adr = @organisation.addresses[0]
  phone = @organisation.phones[0]

  @form_data = {
    given_name: @id_token_details['given_name'],
    family_name: @id_token_details['family_name'],
    email: @id_token_details['email'],
    org_name: @organisation.name,
    contacts_count: @contacts.flatten.count,
    currency: @organisation.base_currency,
    timezone: @organisation.timezone,
    street: adr ? adr.address_line1 : '',
    city: adr ? adr.address_line2 : '',
    postal_code: adr ? adr.postal_code : '',
    phone: phone ? "#{phone.phone_type}: #{phone.phone_area_code} #{phone.phone_number}" : '',
    password: 'Set a password to create your account!'
  }

  puts "@form_data:::::: #{@form_data}"

  @auth_url = xero_client.authorization_url

  haml :home
end

post '/xero-signup' do
  @params = params.reject { |k, v| ["password", "password_confirmation"].include? k }
  haml :dashboard
end
