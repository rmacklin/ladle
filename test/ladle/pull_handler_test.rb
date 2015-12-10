require 'test_helper'

require 'ladle/pull_handler'
require 'ladle/pull_request_info'
require 'ladle/changed_files'
require 'ladle/file_filter'

class PullHandlerTest < ActiveSupport::TestCase
  setup do
    user = create(:user)
    @repository = Repository.create!(name: 'xanderstrike/test', webhook_secret: 'whatever', access_via: user)
    @pull_request = create(:pull_request, repository: @repository, number: 30, html_url: 'www.test.com')
  end

  test 'does nothing when there are not stewards' do
    client = mock('repository_client')
    client.expects(:pull_request).with(@pull_request.number).returns(
      Ladle::PullRequestInfo.new('branch_head', 'base_head')
    )

    changed_files = Ladle::ChangedFiles.new
    changed_files.add_file_change(build(:file_change, status: :added, file: 'one.rb'))
    changed_files.add_file_change(build(:file_change, status: :modified, file: 'sub/marine.rb'))
    client.expects(:pull_request_files).with(@pull_request.number).returns(changed_files)

    client.expects(:contents).with(path: 'sub/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)

    logger_mock = mock
    logger_mock.expects(:info).with('No stewards found. Doing nothing.')
    Rails.stubs(:logger).returns(logger_mock)

    Ladle::PullHandler.new(client, mock('notifier')).handle(@pull_request)
  end

  test 'notifies stewards' do
    client = mock('repository_client')
    client.expects(:pull_request).with(@pull_request.number).returns(
      Ladle::PullRequestInfo.new('branch_head', 'base_head')
    )

    changed_files = Ladle::ChangedFiles.new
    changed_files.add_file_change(build(:file_change, status: :added, file: 'one.rb', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1, deletions: 1))
    client.expects(:pull_request_files).with(@pull_request.number).returns(changed_files)

    client.expects(:contents).with(path: 'sub/stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - xanderstrike
        - fadsfadsfadsfadsf
    YAML

    client.expects(:contents).with(path: 'stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - github_username: bob
          include: "**.rb"
          exclude: "**.txt"
        - xanderstrike
    YAML

    expected_stewards_changes_view = build(:steward_changes_view,
                                           stewards_file: 'stewards.yml',
                                           changes:       [
                                                            build(:file_change, status: :added, file: 'one.rb', additions: 1),
                                                            build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1, deletions: 1),
                                                          ])

    expected_sub_stewards_changes_view = build(:steward_changes_view,
                                               stewards_file: 'sub/stewards.yml',
                                               changes:       [
                                                                build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1, deletions: 1),
                                                              ])
    notifier = mock
    notifier.expects(:notify)
      .with({
              'xanderstrike'      => {
                'sub/stewards.yml' => [expected_sub_stewards_changes_view],
                'stewards.yml'     => [expected_stewards_changes_view]
              },
              'fadsfadsfadsfadsf' => {
                'sub/stewards.yml' => [expected_sub_stewards_changes_view]
              },
              'bob'               => {
                'stewards.yml' => [build(:steward_changes_view,
                                         stewards_file: 'stewards.yml',
                                         file_filter:   Ladle::FileFilter.new(
                                           include_patterns: ["**.rb"],
                                           exclude_patterns: ["**.txt"]
                                         ),
                                         changes:       [
                                                          build(:file_change, status: :added, file: 'one.rb', additions: 1),
                                                          build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1, deletions: 1),
                                                        ])
                ]
              }
            })

    Ladle::PullHandler.new(client, notifier).handle(@pull_request)
  end

  test 'notifies old stewards' do
    client = mock('repository_client')
    client.expects(:pull_request).with(@pull_request.number).returns(
      Ladle::PullRequestInfo.new('branch_head', 'base_head')
    )

    changed_files = Ladle::ChangedFiles.new
    changed_files.add_file_change(build(:file_change, status: :removed, file: 'stewards.yml', deletions: 1))
    changed_files.add_file_change(build(:file_change, status: :added, file: 'one.rb', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :modified, file: 'sub/stewards.yml', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :removed, file: 'sub2/sandwich', deletions: 1))
    changed_files.add_file_change(build(:file_change, status: :added, file: 'sub2/stewards.yml', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :removed, file: 'sub3/stewards.yml', deletions: 1))
    client.expects(:pull_request_files).with(@pull_request.number).returns(changed_files)

    # sub3/stewards.yml removed by branch
    client.expects(:contents).with(path: 'sub3/stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - xanderstrike
        - bob
    YAML
    client.expects(:contents).with(path: 'sub3/stewards.yml', ref: 'branch_head').never

    # sub2/stewards.yml added by branch
    client.expects(:contents).with(path: 'sub2/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'sub2/stewards.yml', ref: 'branch_head').returns(<<-YAML)
      stewards:
        - hamburglar
    YAML

    # sub/stewards.yml exists on both, changed by branch
    client.expects(:contents).with(path: 'sub/stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - jeb
    YAML

    client.expects(:contents).with(path: 'sub/stewards.yml', ref: 'branch_head').returns(<<-YAML)
      stewards:
        - xanderstrike
        - fadsfadsfadsfadsf
    YAML

    # stewards.yml exists on base
    client.expects(:contents).with(path: 'stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - xanderstrike
        - bob
    YAML
    client.expects(:contents).with(path: 'stewards.yml', ref: 'branch_head').never

    expected_stewards_changes_view = build(:steward_changes_view,
                                           stewards_file: 'stewards.yml',
                                           changes:       [
                                                            build(:file_change, status: :removed, file: 'stewards.yml', deletions: 1),
                                                            build(:file_change, status: :added, file: 'one.rb', additions: 1),
                                                            build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1),
                                                            build(:file_change, status: :modified, file: 'sub/stewards.yml', additions: 1),
                                                            build(:file_change, status: :removed, file: 'sub2/sandwich', deletions: 1),
                                                            build(:file_change, status: :added, file: 'sub2/stewards.yml', additions: 1),
                                                            build(:file_change, status: :removed, file: 'sub3/stewards.yml', deletions: 1)
                                                          ])

    expected_sub_stewards_changes_view = build(:steward_changes_view,
                                               stewards_file: 'sub/stewards.yml',
                                               changes:       [
                                                                build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1),
                                                                build(:file_change, status: :modified, file: 'sub/stewards.yml', additions: 1)
                                                              ])

    expected_sub2_stewards_changes_view = build(:steward_changes_view,
                                               stewards_file: 'sub2/stewards.yml',
                                               changes:       [
                                                                build(:file_change, status: :removed, file: 'sub2/sandwich', deletions: 1),
                                                                build(:file_change, status: :added, file: 'sub2/stewards.yml', additions: 1)
                                                              ])

    expected_sub3_stewards_changes_view = build(:steward_changes_view,
                                                stewards_file: 'sub3/stewards.yml',
                                                changes:       [
                                                                 build(:file_change, status: :removed, file: 'sub3/stewards.yml', deletions: 1)
                                                               ])

    notifier = mock
    notifier.expects(:notify)
      .with({
              'xanderstrike'      => {
                'sub/stewards.yml'  => [expected_sub_stewards_changes_view],
                'stewards.yml'      => [expected_stewards_changes_view],
                'sub3/stewards.yml' => [expected_sub3_stewards_changes_view],
              },
              'fadsfadsfadsfadsf' => {
                'sub/stewards.yml' => [expected_sub_stewards_changes_view]
              },
              'bob'               => {
                'stewards.yml'      => [expected_stewards_changes_view],
                'sub3/stewards.yml' => [expected_sub3_stewards_changes_view]
              },
              'jeb'               => {
                'sub/stewards.yml' => [expected_sub_stewards_changes_view]
              },
              'hamburglar'        => {
                'sub2/stewards.yml' => [expected_sub2_stewards_changes_view]
              },
            })

    Ladle::PullHandler.new(client, notifier).handle(@pull_request)
  end

  test 'notify - stewards file not in changes_view' do
    client = mock('repository_client')
    client.expects(:pull_request).with(@pull_request.number).returns(
      Ladle::PullRequestInfo.new('branch_head', 'base_head')
    )

    changed_files = Ladle::ChangedFiles.new
    changed_files.add_file_change(build(:file_change, status: :added, file: 'goodbye/kitty/sianara.txt', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :added, file: 'hello/kitty/what/che.txt', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :removed, file: 'hello/kitty/what/is/stewards.yml', deletions: 1))
    client.expects(:pull_request_files).with(@pull_request.number).returns(changed_files)

    client.expects(:contents).with(path: 'goodbye/kitty/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'goodbye/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'hello/kitty/what/is/stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - xanderstrike
        - bleh
    YAML
    client.expects(:contents).with(path: 'hello/kitty/what/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'hello/kitty/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'hello/stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - xanderstrike
    YAML

    client.expects(:contents).with(path: 'stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)

    expected_stewards_changes_view = build(:steward_changes_view,
                                    stewards_file: 'hello/stewards.yml',
                                    changes:       [
                                                     build(:file_change, status: :added, file: 'hello/kitty/what/che.txt', additions: 1),
                                                     build(:file_change, status: :removed, file: 'hello/kitty/what/is/stewards.yml', deletions: 1),
                                                   ])

    expected_sub_stewards_changes_view = build(:steward_changes_view,
                                                  stewards_file: 'hello/kitty/what/is/stewards.yml',
                                                  changes:       [
                                                                   build(:file_change, status: :removed, file: 'hello/kitty/what/is/stewards.yml', deletions: 1),
                                                                 ])

    notifier = mock
    notifier.expects(:notify)
      .with({
              'xanderstrike' => {
                'hello/stewards.yml' => [expected_stewards_changes_view],
                'hello/kitty/what/is/stewards.yml' => [expected_sub_stewards_changes_view]
              },
              'bleh'         => {
                'hello/kitty/what/is/stewards.yml' => [expected_sub_stewards_changes_view]
              }
            })

    Ladle::PullHandler.new(client, notifier).handle(@pull_request)
  end

  test 'handle handles invalid stewards files ' do
    client = mock('repository_client')
    client.expects(:pull_request).with(@pull_request.number).returns(
      Ladle::PullRequestInfo.new('branch_head', 'base_head')
    )

    changed_files = Ladle::ChangedFiles.new
    changed_files.add_file_change(build(:file_change, status: :added, file: 'one.rb', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1, deletions: 1))
    client.expects(:pull_request_files).with(@pull_request.number).returns(changed_files)

    client.expects(:contents).with(path: 'sub/stewards.yml', ref: 'base_head').returns(<<-YAML)
      SOME WORDS
    YAML

    client.expects(:contents).with(path: 'stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - xanderstrike
        - fadsfadsfadsfadsf
    YAML

    expected_stewards_changes_view = {
      'stewards.yml' => [build(:steward_changes_view,
                              stewards_file: 'stewards.yml',
                              changes:       [
                                               build(:file_change, status: :added, file: 'one.rb', additions: 1),
                                               build(:file_change, status: :modified, file: 'sub/marine.rb', additions: 1, deletions: 1),
                                             ])]
    }

    notifier = mock
    notifier.expects(:notify)
      .with({
              'xanderstrike'      => expected_stewards_changes_view,
              'fadsfadsfadsfadsf' => expected_stewards_changes_view,
            })

    Rails.logger.expects(:error).with(regexp_matches(/Error parsing file sub\/stewards.yml: Stewards file must contain a hash\n.*/))

    Ladle::PullHandler.new(client, notifier).handle(@pull_request)
  end

  test 'handle omits notifying of views/stewards without changes' do
    client = mock('repository_client')
    client.expects(:pull_request).with(@pull_request.number).returns(
      Ladle::PullRequestInfo.new('branch_head', 'base_head')
    )

    changed_files = Ladle::ChangedFiles.new
    changed_files.add_file_change(build(:file_change, status: :added, file: 'hello/kitty/what/is/your/favorite_food.yml', additions: 1))
    changed_files.add_file_change(build(:file_change, status: :added, file: 'hello/kitty/what/is/your/name.txt', additions: 1))
    client.expects(:pull_request_files).with(@pull_request.number).returns(changed_files)

    client.expects(:contents).with(path: 'hello/kitty/what/is/your/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'hello/kitty/what/is/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'hello/kitty/what/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)
    client.expects(:contents).with(path: 'hello/kitty/stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)

    client.expects(:contents).with(path: 'hello/stewards.yml', ref: 'base_head').returns(<<-YAML)
      stewards:
        - xanderstrike
        - github_username: bob
          include: "*.bin"
    YAML

    client.expects(:contents).with(path: 'stewards.yml', ref: 'base_head').raises(Ladle::RemoteFileNotFound)

    notifier = mock
    notifier.stubs(:id).returns(1)
    notifier.expects(:notify)
      .with({
              'xanderstrike' => {
                'hello/stewards.yml' => [build(:steward_changes_view,
                                              stewards_file: 'hello/stewards.yml',
                                              changes:       [
                                                               build(:file_change, status: :added, file: 'hello/kitty/what/is/your/favorite_food.yml', additions: 1),
                                                               build(:file_change, status: :added, file: 'hello/kitty/what/is/your/name.txt', additions: 1)
                                                             ])],
              },
            })

    Ladle::PullHandler.new(client, notifier).handle(@pull_request)
  end

  test "resolve_stewards_scope" do
    registry = {
      'xanderstrike' => {
        'stewards.yml'      => [build(:steward_changes_view, stewards_file: 'stewards.yml')],
        'sub/stewards.yml'  => [build(:steward_changes_view, stewards_file: 'sub/stewards.yml')],
        'sub3/stewards.yml' => [build(:steward_changes_view, stewards_file: 'sub3/stewards.yml')],
      }
    }

    changed_files = Ladle::ChangedFiles.new
    changed_files.add_file_change(build(:file_change, file: 'stewards.yml'))
    changed_files.add_file_change(build(:file_change, file: 'one.rb'))
    changed_files.add_file_change(build(:file_change, file: 'sub/marine.rb'))
    changed_files.add_file_change(build(:file_change, file: 'sub/stewards.yml'))
    changed_files.add_file_change(build(:file_change, file: 'sub2/sandwich'))
    changed_files.add_file_change(build(:file_change, file: 'sub3/stewards.yml'))

    handler = Ladle::PullHandler.new(mock('client'), mock('notifier'))
    resolved_stewards_registry = handler.send(:resolve_stewards_scope, registry, changed_files)

    expected_changes_view = Ladle::StewardChangesView.new(
      stewards_file: 'stewards.yml',
      changes:       [
                       build(:file_change, file: 'stewards.yml'),
                       build(:file_change, file: 'one.rb'),
                       build(:file_change, file: 'sub/marine.rb'),
                       build(:file_change, file: 'sub/stewards.yml'),
                       build(:file_change, file: 'sub2/sandwich'),
                       build(:file_change, file: 'sub3/stewards.yml')
                     ])

    assert_equal [expected_changes_view], resolved_stewards_registry['xanderstrike']['stewards.yml']

    expected_changes_view = Ladle::StewardChangesView.new(
      stewards_file: 'sub/stewards.yml',
      changes:       [
                       build(:file_change, file: 'sub/marine.rb'),
                       build(:file_change, file: 'sub/stewards.yml'),
                     ])

    assert_equal [expected_changes_view], resolved_stewards_registry['xanderstrike']['sub/stewards.yml']

    expected_changes_view = Ladle::StewardChangesView.new(
      stewards_file: 'sub3/stewards.yml',
      changes:       [
                       build(:file_change, file: 'sub3/stewards.yml')
                     ])

    assert_equal [expected_changes_view], resolved_stewards_registry['xanderstrike']['sub3/stewards.yml']
  end

  private

  def stub_stewards_file_contents(client, contents, path:, ref:)
    client.expects(:contents).with(path: path, ref: ref).returns(contents)
  end
end
