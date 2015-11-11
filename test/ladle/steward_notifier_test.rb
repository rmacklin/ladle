require 'test_helper'
require 'steward_notifier'

class StewardNotifierTest < ActionController::TestCase
  include VCRHelpers

  PullRequestLike = Struct.new(:html_url, :title, :description)

  setup do
    @stewards = {
      'xanderstrike' => ['/stewards.yml', '/test/stewards.yml'],
      'boop'         => ['/stewards.yml']
    }
    @notifier = StewardNotifier.new(@stewards, 'XanderStrike/test', PullRequestLike.new('https://github.com/XanderStrike/test/pull/11'))
  end

  test 'assigns the stewards and the handler' do
    assert_equal @stewards, @notifier.instance_variable_get(:@stewards_map)
    assert_equal 'https://github.com/XanderStrike/test/pull/11', @notifier.instance_variable_get(:@pull_request).html_url
  end

  test 'notify should send emails to users' do
    user = create(:user, email: 'xander@strike.com', github_username: 'xanderstrike')
    @notifier.expects(:send_email).with(user, ['/stewards.yml', '/test/stewards.yml'])
    @notifier.notify
  end

  test 'send_email uses UserMailer' do
    ActionMailer::Base.deliveries.clear
    user = create(:user, email: 'hello@kitty.com')

    @notifier.send(:send_email, user, ['/stewards.yml', '/test/stewards.yml'])

    notify_email = ActionMailer::Base.deliveries.last

    assert_equal "[XanderStrike/test] Ladle Alert: New Pull Request", notify_email.subject
    assert_equal 'hello@kitty.com', notify_email.to[0]
  end
end
