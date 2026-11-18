# frozen_string_literal: true

# Deterministic seed verification for the tester environment.
#
#   bin/rails runner 'TesterEnv::Verify.run!'
#
# Asserts the seeded fixture state through the app's own scopes, filters and
# search code (the same surfaces the dashboard renders). Exits non-zero on the
# first mismatch group so `./tester-env verify` fails loudly.

module TesterEnv
  module Verify
    TEMPLATE_NAMES = [
      'Consulting Services Agreement', 'Mutual NDA', 'Statement of Work',
      'Software License Agreement', 'Data Processing Addendum', 'Employment Offer Letter'
    ].freeze

    FOLDERED_TEMPLATES = {
      'Sales Contracts' => ['Software License Agreement', 'Data Processing Addendum'],
      'HR Onboarding' => ['Employment Offer Letter']
    }.freeze

    SUBMISSION_NAMES = [
      'Consulting Services Agreement — Brightpath Health', 'Mutual NDA — Fernwood Capital',
      'Statement of Work — Larkspur Retail', 'Software License Agreement — Meridian Logistics',
      'Data Processing Addendum — Cobalt Freight', 'Employment Offer Letter — Rosa Delgado',
      'Software License Agreement — Northgate Media', 'Mutual NDA — Halcyon Studio'
    ].freeze

    STATUS_COUNTS = {
      'completed' => 2, 'pending' => 4, 'declined' => 1, 'expired' => 1,
      'sent' => 3, 'opened' => 2, 'partially_completed' => 2
    }.freeze

    module_function

    def run!
      account = Account.order(:id).first
      raise 'No account found' if account.nil?

      admin = User.find_by!(email: 'admin@tester-env.local')
      checks = []

      check(checks, 'account is Tester Env', account.name, 'Tester Env')
      check(checks, 'users', User.where(account:).count, 4)
      ['marco.silva', 'priya.raman', 'dana.okafor'].each do |mailbox|
        email = "#{mailbox}@tester-env.local"
        user = User.find_by(email:)
        check(checks, "#{email} signs in with the seed password", true, user&.valid_password?('TesterEnv123!'))
        check(checks, "#{email} is active", true, user.present? && !user.archived_at?)
      end

      folders = account.template_folders
      check(checks, 'template folders', folders.count, 3)
      check(checks, 'default folder', true, folders.exists?(name: TemplateFolder::DEFAULT_NAME))
      FOLDERED_TEMPLATES.each do |folder_name, names|
        folder = folders.find_by(name: folder_name)
        check(checks, "folder #{folder_name} templates", names.sort, folder&.templates&.order(:name)&.pluck(:name)&.sort)
      end

      templates = account.templates.order(:name)
      check(checks, 'templates', templates.count, 6)
      check(checks, 'template names', TEMPLATE_NAMES.sort, templates.pluck(:name).sort)
      templates.each do |template|
        document = template.documents.first
        check(checks, "#{template.name} has a PDF document", true,
              document.present? && document.filename.to_s.end_with?('.pdf'))
        check(checks, "#{template.name} has processed page metadata", 1,
              document&.metadata&.dig('pdf', 'number_of_pages'))
        check(checks, "#{template.name} has preview images", true, document.present? && document.preview_images.any?)
        check(checks, "#{template.name} fields reference its parties", true,
              template.fields.any? && template.fields.all? { |f| template.submitters.pluck('uuid').include?(f['submitter_uuid']) })
      end
      check(checks, 'Consulting Services Agreement created_at', Time.utc(2026, 9, 12, 10, 15).to_i,
            templates.find_by(name: 'Consulting Services Agreement').created_at.to_i)
      check(checks, 'Employment Offer Letter folder', 'HR Onboarding',
            templates.find_by(name: 'Employment Offer Letter').folder.name)

      active = Submission.active.joins(:template).where(templates: { archived_at: nil })
      check(checks, 'active submissions', active.count, 7)
      check(checks, 'all submissions', Submission.count, 8)
      check(checks, 'archived submissions', Submission.archived.count, 1)
      check(checks, 'submission names', SUBMISSION_NAMES.sort, Submission.pluck(:name).sort)
      STATUS_COUNTS.each do |status, count|
        check(checks, "status filter #{status}", count,
              Submissions::Filter.call(active, admin, { 'status' => status }).count)
      end
      check(checks, 'status filter all', 7, Submissions::Filter.call(active, admin, {}).count)

      consulting = Submission.find_by(name: 'Consulting Services Agreement — Brightpath Health')
      check(checks, 'completed submission completed_at', Time.utc(2026, 10, 3, 14, 12).to_i,
            consulting.completed_at.to_i)
      check(checks, 'completed submission created_at', Time.utc(2026, 10, 3, 9, 20).to_i, consulting.created_at.to_i)
      check(checks, 'completed submitter values', true,
            consulting.submitters.find_by(name: 'Olivia Bennett').values.values.include?('Brightpath Health LLC'))
      check(checks, 'completed submitter date value', true,
            consulting.submitters.find_by(name: 'Olivia Bennett').values.values.include?('2026-10-03'))

      fernwood = Submission.find_by(name: 'Mutual NDA — Fernwood Capital')
      check(checks, 'second party completed values', true,
            fernwood.submitters.find_by(name: 'Dana Okafor').values.values.include?(30))
      check(checks, 'partially completed submission', nil,
            Submission.find_by(name: 'Software License Agreement — Northgate Media').completed_at)
      check(checks, 'expired submission expires in the past', true,
            Submission.find_by(name: 'Employment Offer Letter — Rosa Delgado').expired?)

      declined_ids = Submission.joins(:submitters).where.not(submitters: { declined_at: nil }).select(:id)
      check(checks, 'declined submissions', 1, Submission.where(id: declined_ids).count)
      Submission.joins(:submitters).where.not(submitters: { declined_at: nil }).find_each do |submission|
        submission.submitters.where.not(declined_at: nil).each do |submitter|
          event = submitter.submission_events.find_by(event_type: 'decline_form')
          # submissions/show.html.erb renders this event's data['reason'] for a
          # declined submitter and 500s when the event is missing.
          check(checks, "#{submitter.name} has a decline reason", true, event&.data&.dig('reason').present?)
          check(checks, "#{submitter.name} decline reason timestamp", submitter.declined_at.to_i,
                event&.event_timestamp&.to_i)
        end
      end

      check(checks, 'template search NDA', 1, Templates.search(admin, Template.all, 'NDA').count)
      check(checks, 'submission search Brightpath', 1,
            Submissions.search(admin, Submission.all, 'Brightpath', search_template: true).count)

      failed = checks.reject { |(_, ok)| ok }
      checks.each { |(label, ok)| puts "  #{ok ? 'PASS' : 'FAIL'} #{label}" }
      abort "tester-env verify: #{failed.size} seed check(s) failed" if failed.any?

      puts "tester-env verify: #{checks.size} seed checks passed"
    end

    def check(checks, label, expected, actual)
      checks << [label, expected == actual]
    end
  end
end
