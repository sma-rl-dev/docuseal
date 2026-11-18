# frozen_string_literal: true

# Deterministic DocuSeal fixture seed for the tester environment.
#
#   bin/rails runner 'TesterEnv::Seed.run!'
#
# (The file is autoloaded by Zeitwerk; ./tester-env seed runs the expression
# above inside the app container.)
#
# Upstream ships no db/seeds.rb or seed task (spec/factories are dev/test only),
# so this mirrors spec/factories/templates.rb with production code paths:
# ActiveStorage blob upload -> Pdfium page read -> Templates::ProcessDocument
# (page count + preview images) -> template.schema/fields.
#
# Idempotent: users keyed by email, folders by name, templates by name,
# submissions by (template, name). Re-running converges on the same state.
# Every visible timestamp is pinned so list/detail dates survive a reset.

module TesterEnv
  module Seed
    PASSWORD = 'TesterEnv123!'
    DOCUMENT_PATH = File.expand_path('sample-document.pdf', __dir__)
    DEFAULT_FOLDER_CREATED_AT = Time.utc(2026, 9, 1, 8, 30)

    USERS = [
      { key: 'marco', email: 'marco.silva@tester-env.local', first_name: 'Marco', last_name: 'Silva',
        created_at: Time.utc(2026, 9, 1, 9, 0) },
      { key: 'priya', email: 'priya.raman@tester-env.local', first_name: 'Priya', last_name: 'Raman',
        created_at: Time.utc(2026, 9, 2, 10, 30) },
      { key: 'dana', email: 'dana.okafor@tester-env.local', first_name: 'Dana', last_name: 'Okafor',
        created_at: Time.utc(2026, 9, 5, 11, 0) }
    ].freeze

    FOLDERS = [
      { key: 'sales', name: 'Sales Contracts', author: 'marco', created_at: Time.utc(2026, 9, 10, 9, 0) },
      { key: 'hr', name: 'HR Onboarding', author: 'priya', created_at: Time.utc(2026, 9, 15, 14, 0) }
    ].freeze

    # Fields are laid out in two columns (first party left, second party right)
    # and reference the single seeded PDF page.
    TEMPLATES = [
      {
        key: 'consulting-services-agreement',
        name: 'Consulting Services Agreement',
        folder: nil,
        author: 'marco',
        created_at: Time.utc(2026, 9, 12, 10, 15),
        submitters: %w[Client Consultant],
        fields: [
          { party: 0, name: 'Client legal name', type: 'text' },
          { party: 0, name: 'Client signatory', type: 'text' },
          { party: 0, name: 'Effective date', type: 'date', preferences: { 'format' => 'DD/MM/YYYY' } },
          { party: 1, name: 'Consultant name', type: 'text' },
          { party: 1, name: 'Consultant signatory', type: 'text' },
          { party: 1, name: 'Engagement start date', type: 'date', preferences: { 'format' => 'DD/MM/YYYY' } }
        ]
      },
      {
        key: 'mutual-nda',
        name: 'Mutual NDA',
        folder: nil,
        author: 'dana',
        created_at: Time.utc(2026, 9, 20, 16, 40),
        submitters: ['Disclosing Party', 'Receiving Party'],
        fields: [
          { party: 0, name: 'Disclosing party name', type: 'text' },
          { party: 0, name: 'NDA effective date', type: 'date', preferences: { 'format' => 'DD/MM/YYYY' } },
          { party: 1, name: 'Receiving party name', type: 'text' },
          { party: 1, name: 'Notice period', type: 'number' },
          { party: 1, name: 'Confidentiality acknowledged', type: 'checkbox' }
        ]
      },
      {
        key: 'statement-of-work',
        name: 'Statement of Work',
        folder: nil,
        author: 'marco',
        created_at: Time.utc(2026, 10, 2, 11, 5),
        submitters: ['Client'],
        fields: [
          { party: 0, name: 'Client name', type: 'text' },
          { party: 0, name: 'Project name', type: 'text' },
          { party: 0, name: 'Fixed fee', type: 'number' },
          { party: 0, name: 'Start date', type: 'date', preferences: { 'format' => 'DD/MM/YYYY' } },
          { party: 0, name: 'Payment terms', type: 'select', options: ['Net 30', 'Net 45', 'Net 60'] }
        ]
      },
      {
        key: 'software-license-agreement',
        name: 'Software License Agreement',
        folder: 'sales',
        author: 'marco',
        created_at: Time.utc(2026, 10, 8, 9, 30),
        submitters: %w[Licensee Licensor],
        fields: [
          { party: 0, name: 'Licensee name', type: 'text' },
          { party: 0, name: 'Licensed seats', type: 'number' },
          { party: 1, name: 'Licensor signatory', type: 'text' },
          { party: 1, name: 'License start date', type: 'date', preferences: { 'format' => 'DD/MM/YYYY' } }
        ]
      },
      {
        key: 'data-processing-addendum',
        name: 'Data Processing Addendum',
        folder: 'sales',
        author: 'dana',
        created_at: Time.utc(2026, 10, 18, 13, 25),
        submitters: %w[Customer Processor],
        fields: [
          { party: 0, name: 'Customer name', type: 'text' },
          { party: 0, name: 'Data categories', type: 'text' },
          { party: 1, name: 'Processor signatory', type: 'text' },
          { party: 1, name: 'Processing region', type: 'select', options: ['EU West / Dublin', 'US East / Virginia'] }
        ]
      },
      {
        key: 'employment-offer-letter',
        name: 'Employment Offer Letter',
        folder: 'hr',
        author: 'priya',
        created_at: Time.utc(2026, 11, 3, 15, 50),
        submitters: ['Candidate'],
        fields: [
          { party: 0, name: 'Candidate name', type: 'text' },
          { party: 0, name: 'Position title', type: 'text' },
          { party: 0, name: 'Annual salary', type: 'number' },
          { party: 0, name: 'Start date', type: 'date', preferences: { 'format' => 'DD/MM/YYYY' } },
          { party: 0, name: 'Offer accepted', type: 'checkbox' }
        ]
      }
    ].freeze

    # Submitter timestamps drive the dashboard status badges:
    # declined_at > completed_at > opened_at > sent_at > awaiting.
    # submission.completed_at is derived from the submitters (all completed).
    SUBMISSIONS = [
      {
        key: 'brightpath-consulting',
        template: 'consulting-services-agreement',
        name: 'Consulting Services Agreement — Brightpath Health',
        created_by: 'marco',
        created_at: Time.utc(2026, 10, 3, 9, 20),
        submitters: [
          { party: 0, name: 'Olivia Bennett', email: 'olivia.bennett@brightpath.example',
            sent_at: Time.utc(2026, 10, 3, 9, 25), opened_at: Time.utc(2026, 10, 3, 10, 2),
            completed_at: Time.utc(2026, 10, 3, 11, 30),
            values: { 'Client legal name' => 'Brightpath Health LLC', 'Client signatory' => 'Olivia Bennett',
                      'Effective date' => '2026-10-03' } },
          { party: 1, name: 'Marco Silva', email: 'marco.silva@tester-env.local',
            sent_at: Time.utc(2026, 10, 3, 9, 25), opened_at: Time.utc(2026, 10, 3, 11, 45),
            completed_at: Time.utc(2026, 10, 3, 14, 12),
            values: { 'Consultant name' => 'Northwind Consulting LLC', 'Consultant signatory' => 'Marco Silva',
                      'Engagement start date' => '2026-10-06' } }
        ]
      },
      {
        key: 'fernwood-nda',
        template: 'mutual-nda',
        name: 'Mutual NDA — Fernwood Capital',
        created_by: 'dana',
        created_at: Time.utc(2026, 9, 24, 10, 5),
        submitters: [
          { party: 0, name: 'Caleb Turner', email: 'caleb.turner@fernwood.example',
            sent_at: Time.utc(2026, 9, 24, 10, 10), opened_at: Time.utc(2026, 9, 24, 12, 30),
            completed_at: Time.utc(2026, 9, 25, 11, 20),
            values: { 'Disclosing party name' => 'Fernwood Capital Partners', 'NDA effective date' => '2026-09-25' } },
          { party: 1, name: 'Dana Okafor', email: 'dana.okafor@tester-env.local',
            sent_at: Time.utc(2026, 9, 24, 10, 10), opened_at: Time.utc(2026, 9, 24, 11, 0),
            completed_at: Time.utc(2026, 9, 25, 16, 40),
            values: { 'Receiving party name' => 'Northwind Consulting LLC', 'Notice period' => 30,
                      'Confidentiality acknowledged' => true } }
        ]
      },
      {
        key: 'larkspur-sow',
        template: 'statement-of-work',
        name: 'Statement of Work — Larkspur Retail',
        created_by: 'marco',
        created_at: Time.utc(2026, 11, 10, 8, 45),
        submitters: [
          { party: 0, name: 'Hannah Whitfield', email: 'hannah.whitfield@larkspur.example',
            sent_at: Time.utc(2026, 11, 10, 8, 50) }
        ]
      },
      {
        key: 'meridian-license',
        template: 'software-license-agreement',
        name: 'Software License Agreement — Meridian Logistics',
        created_by: 'marco',
        created_at: Time.utc(2026, 10, 12, 9, 0),
        submitters: [
          { party: 0, name: 'Amir Haddad', email: 'amir.haddad@meridianlogistics.example',
            sent_at: Time.utc(2026, 10, 12, 9, 10), opened_at: Time.utc(2026, 10, 12, 10, 0),
            completed_at: Time.utc(2026, 10, 13, 15, 30),
            values: { 'Licensee name' => 'Meridian Logistics Inc.', 'Licensed seats' => 250 } },
          { party: 1, name: 'Marco Silva', email: 'marco.silva@tester-env.local',
            sent_at: Time.utc(2026, 10, 12, 9, 10), opened_at: Time.utc(2026, 10, 12, 11, 15) }
        ]
      },
      {
        key: 'cobalt-dpa',
        template: 'data-processing-addendum',
        name: 'Data Processing Addendum — Cobalt Freight',
        created_by: 'dana',
        created_at: Time.utc(2026, 10, 20, 10, 15),
        submitters: [
          { party: 0, name: 'Sofia Marchetti', email: 'sofia.marchetti@cobaltfreight.example',
            sent_at: Time.utc(2026, 10, 20, 10, 20), opened_at: Time.utc(2026, 10, 21, 8, 30),
            declined_at: Time.utc(2026, 10, 22, 9, 40),
            decline_reason: 'Budget sign-off moved to the next fiscal quarter.' },
          { party: 1, name: 'Dana Okafor', email: 'dana.okafor@tester-env.local',
            sent_at: Time.utc(2026, 10, 20, 10, 20) }
        ]
      },
      {
        key: 'delgado-offer',
        template: 'employment-offer-letter',
        name: 'Employment Offer Letter — Rosa Delgado',
        created_by: 'priya',
        created_at: Time.utc(2026, 10, 5, 9, 0),
        expire_at: Time.utc(2026, 10, 20, 9, 0),
        submitters: [
          { party: 0, name: 'Rosa Delgado', email: 'rosa.delgado@example.com',
            sent_at: Time.utc(2026, 10, 5, 9, 5) }
        ]
      },
      {
        key: 'northgate-license',
        template: 'software-license-agreement',
        name: 'Software License Agreement — Northgate Media',
        created_by: 'marco',
        created_at: Time.utc(2026, 11, 6, 14, 20),
        submitters: [
          { party: 0, name: 'Ethan Cole', email: 'ethan.cole@northgate.example',
            sent_at: Time.utc(2026, 11, 6, 14, 25), opened_at: Time.utc(2026, 11, 6, 15, 0),
            completed_at: Time.utc(2026, 11, 7, 10, 15),
            values: { 'Licensee name' => 'Northgate Media Group', 'Licensed seats' => 40 } },
          { party: 1, name: 'Marco Silva', email: 'marco.silva@tester-env.local',
            sent_at: Time.utc(2026, 11, 6, 14, 25), opened_at: Time.utc(2026, 11, 7, 9, 0) }
        ]
      },
      {
        key: 'halcyon-nda',
        template: 'mutual-nda',
        name: 'Mutual NDA — Halcyon Studio',
        created_by: 'dana',
        created_at: Time.utc(2026, 9, 28, 11, 0),
        archived_at: Time.utc(2026, 11, 5, 16, 20),
        submitters: [
          { party: 0, name: 'Nina Petrov', email: 'nina.petrov@halcyon.example',
            sent_at: Time.utc(2026, 9, 28, 11, 5), opened_at: Time.utc(2026, 9, 28, 13, 0),
            completed_at: Time.utc(2026, 9, 29, 15, 10),
            values: { 'Disclosing party name' => 'Halcyon Studio Ltd', 'NDA effective date' => '2026-09-30' } },
          { party: 1, name: 'Dana Okafor', email: 'dana.okafor@tester-env.local',
            sent_at: Time.utc(2026, 9, 28, 11, 5), opened_at: Time.utc(2026, 9, 28, 14, 0),
            completed_at: Time.utc(2026, 9, 30, 10, 5),
            values: { 'Receiving party name' => 'Northwind Consulting LLC', 'Notice period' => 15,
                      'Confidentiality acknowledged' => true } }
        ]
      }
    ].freeze

    module_function

    def run!
      account = Account.order(:id).first
      raise 'No account found: run ./tester-env deploy (first-run /setup) first' if account.nil?

      admin = User.find_by!(email: 'admin@tester-env.local')

      users = seed_users(account)
      # Deploy creates the account but not its Default folder; pin it so a fresh
      # seed has the same dates as a re-seed.
      account.default_template_folder.update_columns(
        created_at: DEFAULT_FOLDER_CREATED_AT, updated_at: DEFAULT_FOLDER_CREATED_AT
      )
      folders = seed_folders(account, users)
      templates = seed_templates(account, users, folders)
      seed_submissions(account, users, templates)

      puts "tester-env seed: #{users.size} seeded users, #{folders.size} folders, " \
           "#{templates.size} templates, #{SUBMISSIONS.size} submissions (admin id #{admin.id})"
    end

    def seed_users(account)
      USERS.to_h do |spec|
        user = User.find_or_initialize_by(email: spec[:email])
        if user.new_record?
          user.assign_attributes(
            account:, first_name: spec[:first_name], last_name: spec[:last_name],
            role: User::ADMIN_ROLE, password: PASSWORD,
            created_at: spec[:created_at], updated_at: spec[:created_at]
          )
          user.save!
        end
        [spec[:key], user]
      end
    end

    def seed_folders(account, users)
      FOLDERS.to_h do |spec|
        folder = account.template_folders.find_or_initialize_by(name: spec[:name], parent_folder_id: nil)
        if folder.new_record?
          folder.assign_attributes(author: users.fetch(spec[:author]),
                                   created_at: spec[:created_at], updated_at: spec[:created_at])
          folder.save!
        end
        [spec[:key], folder]
      end
    end

    def seed_templates(account, users, folders)
      TEMPLATES.to_h do |spec|
        template = account.templates.find_or_initialize_by(name: spec[:name])

        if template.new_record?
          template.assign_attributes(
            author: users.fetch(spec[:author]),
            folder: spec[:folder] ? folders.fetch(spec[:folder]) : account.default_template_folder,
            slug: spec[:key], source: 'native', submitters: party_submitters(spec),
            fields: [], schema: [], preferences: {},
            created_at: spec[:created_at], updated_at: spec[:created_at]
          )
          template.save!
        end

        attachment = template.documents.first
        if attachment.blank?
          template.schema = []
          attachment = attach_document(template, spec)
        end

        if template.fields.blank?
          template.fields = build_fields(spec, attachment.uuid)
          template.save!
        end

        template.update_columns(updated_at: spec[:created_at])
        [spec[:key], template]
      end
    end

    def seed_submissions(account, users, templates)
      SUBMISSIONS.each do |spec|
        template = templates.fetch(spec[:template])
        submission = template.submissions.find_or_initialize_by(name: spec[:name])

        if submission.new_record?
          created_by = users.fetch(spec[:created_by])
          submission.assign_attributes(
            account:, created_by_user: created_by, source: 'invite', submitters_order: 'random',
            template_fields: template.fields, template_schema: template.schema,
            template_submitters: template.submitters, variables: {}, variables_schema: nil,
            preferences: {}, slug: spec[:key], expire_at: spec[:expire_at],
            archived_at: spec[:archived_at],
            created_at: spec[:created_at], updated_at: spec[:created_at]
          )
          submission.save!

          spec[:submitters].each do |submitter_spec|
            party = template.submitters.fetch(submitter_spec[:party])
            submission.submitters.create!(
              account:, uuid: party['uuid'], slug: "#{spec[:key]}-#{submitter_spec[:party]}",
              name: submitter_spec[:name], email: submitter_spec[:email],
              values: submitter_values(template, party['uuid'], submitter_spec[:values]),
              preferences: { 'send_email' => false },
              sent_at: submitter_spec[:sent_at], opened_at: submitter_spec[:opened_at],
              completed_at: submitter_spec[:completed_at], declined_at: submitter_spec[:declined_at],
              created_at: spec[:created_at], updated_at: spec[:created_at]
            )
          end

          completed_ats = spec[:submitters].filter_map { |s| s[:completed_at] }
          if completed_ats.size == spec[:submitters].size
            submission.update_columns(completed_at: completed_ats.max, updated_at: spec[:created_at])
          else
            submission.update_columns(updated_at: spec[:created_at])
          end
        end

        seed_decline_events(submission, spec)
      end
    end

    # The submission detail page reads the decline_form event's reason for any
    # declined submitter, so the event is part of the fixture, not an extra.
    def seed_decline_events(submission, spec)
      spec[:submitters].each do |submitter_spec|
        next if submitter_spec[:decline_reason].blank? || submitter_spec[:declined_at].blank?

        submitter = submission.submitters.find_by(name: submitter_spec[:name])
        next if submitter.nil?

        event = submitter.submission_events.find_or_initialize_by(event_type: 'decline_form')
        next unless event.new_record?

        at = submitter_spec[:declined_at]
        event.assign_attributes(
          data: { 'reason' => submitter_spec[:decline_reason] },
          event_timestamp: at, created_at: at, updated_at: at
        )
        event.save!
      end
    end

    def party_submitters(spec)
      spec[:submitters].each_with_index.map do |name, index|
        { 'name' => name, 'uuid' => uuid("#{spec[:key]}/party/#{index}") }
      end
    end

    def build_fields(spec, attachment_uuid)
      spec[:fields].each_with_index.map do |field, index|
        field_hash = {
          'uuid' => uuid("#{spec[:key]}/field/#{field[:name]}"),
          'submitter_uuid' => uuid("#{spec[:key]}/party/#{field[:party]}"),
          'name' => field[:name],
          'type' => field[:type],
          'required' => true,
          'preferences' => field[:preferences] || {},
          'areas' => [{
            'x' => field[:party].zero? ? 0.08 : 0.55,
            'y' => 0.16 + (0.06 * index),
            'w' => 0.32,
            'h' => 0.04,
            'attachment_uuid' => attachment_uuid,
            'page' => 0
          }]
        }
        if field[:options]
          field_hash['options'] = field[:options].map do |option|
            { 'value' => option, 'uuid' => uuid("#{spec[:key]}/field/#{field[:name]}/option/#{option}") }
          end
        end
        field_hash
      end
    end

    def submitter_values(template, submitter_uuid, values)
      return {} if values.blank?

      template.fields.each_with_object({}) do |field, acc|
        next unless field['submitter_uuid'] == submitter_uuid
        next unless values.key?(field['name'])

        acc[field['uuid']] = values[field['name']]
      end
    end

    def attach_document(template, spec)
      attachment = ActiveStorage::Attachment.create!(
        blob: ActiveStorage::Blob.create_and_upload!(
          io: File.open(DOCUMENT_PATH), filename: "#{spec[:key]}.pdf", content_type: 'application/pdf'
        ),
        name: :documents, record: template
      )
      data = attachment.download
      Pdfium::Document.open_io(StringIO.new(data)) do |doc|
        Templates::ProcessDocument.call(attachment, data, doc:)
      end
      template.schema << { 'attachment_uuid' => attachment.uuid, 'name' => spec[:key] }
      template.save!
      attachment
    end

    def uuid(key)
      Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "tester-env/docuseal/#{key}")
    end
  end
end
