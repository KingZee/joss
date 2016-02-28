class Paper < ActiveRecord::Base

  belongs_to  :submitting_author,
              :class_name => 'User',
              :validate => true,
              :foreign_key => "user_id"

  include AASM

  aasm :column => :state do
    state :submitted, :initial => true
    state :under_review, :before_enter => :create_review_issue
    state :review_completed
    state :superceded
    state :accepted
    state :rejected

    event :reject do
      transitions :to => :rejected
    end

    event :start_review do
      transitions :from => :submitted, :to => :under_review
    end
  end

  VISIBLE_STATES = [
    "accepted",
    "superceded"
  ]

  IN_PROGRESS_STATES = [
    "submitted",
    "under_review"
  ]

  scope :recent, lambda { where('created_at > ?', 1.week.ago) }
  scope :submitted, lambda { where('state = ?', 'submitted') }
  scope :in_progress, -> { where(:state => IN_PROGRESS_STATES) }
  scope :visible, -> { where(:state => VISIBLE_STATES) }
  scope :everything, lambda { where('state != ?', 'rejected') }

  before_create :set_sha

  validates_presence_of :title
  validates_presence_of :repository_url, :message => "^Repository address can't be blank"
  validates_presence_of :archive_doi, :message => "^DOI can't be blank"
  validates_presence_of :body, :message => "^Description can't be blank"

  def self.featured
    # TODO: Make this a thing
    Paper.first
  end

  def self.popular
    recent
  end

  def to_param
    sha
  end

  def pretty_repository_name
    if repository_url.include?('github.com')
      name, owner = repository_url.scan(/(?<=github.com\/).*/i).first.split('/')
      return "#{name} / #{owner}"
    else
      return repository_url
    end
  end

  def pretty_doi
    matches = archive_doi.scan(/\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'<>])\S)+)\b/).flatten

    if matches.any?
      return matches.first
    else
      return archive_doi
    end
  end

  def create_review_issue
    return false if review_issue_id
    issue = GITHUB.create_issue("arfon/joss-reviews",
                                "Submission: #{self.title}",
                                review_body,
                                { :labels => "review" })

    set_review_issue(issue)
  end

  def set_review_issue(issue)
    self.update_attribute(:review_issue_id, issue.number)
  end

  def update_review_issue(comment)
    GITHUB.add_comment("arfon/joss-reviews", self.review_issue_id, comment)
  end

  def review_url
    "https://github.com/arfon/joss-reviews/issues/#{self.review_issue_id}"
  end

  def review_body
    ActionView::Base.new(Rails.configuration.paths['app/views']).render(
      :template => 'shared/review_body', :format => :txt,
      :locals => { :paper => self }
    )
  end

  def pretty_state
    state.humanize.downcase
  end

private

  def set_sha
    self.sha = SecureRandom.hex
  end
end
