/// Lightweight GitHub data models used by the GitHub sub-app.
///
/// Only the fields the UI renders are parsed; unknown fields are ignored so
/// GitHub API additions never break deserialization.
library;

class GitHubUser {
  const GitHubUser({
    required this.login,
    required this.avatarUrl,
    required this.htmlUrl,
    this.name,
    this.bio,
    this.company,
    this.location,
    this.email,
    this.blog,
    this.followers = 0,
    this.following = 0,
    this.publicRepos = 0,
    this.createdAt,
  });

  final String login;
  final String avatarUrl;
  final String htmlUrl;
  final String? name;
  final String? bio;
  final String? company;
  final String? location;
  final String? email;
  final String? blog;
  final int followers;
  final int following;
  final int publicRepos;
  final DateTime? createdAt;

  /// Display name, falling back to the login handle.
  String get displayName => (name == null || name!.isEmpty) ? login : name!;

  factory GitHubUser.fromJson(Map<String, dynamic> json) => GitHubUser(
        login: json['login'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
        htmlUrl: json['html_url'] as String? ?? '',
        name: json['name'] as String?,
        bio: json['bio'] as String?,
        company: json['company'] as String?,
        location: json['location'] as String?,
        email: json['email'] as String?,
        blog: json['blog'] as String?,
        followers: (json['followers'] as num?)?.toInt() ?? 0,
        following: (json['following'] as num?)?.toInt() ?? 0,
        publicRepos: (json['public_repos'] as num?)?.toInt() ?? 0,
        createdAt:
            (json['created_at'] as String?) != null
                ? DateTime.tryParse(json['created_at'] as String)
                : null,
      );
}

class GitHubRepo {
  const GitHubRepo({
    required this.id,
    required this.name,
    required this.fullName,
    required this.htmlUrl,
    required this.ownerAvatarUrl,
    this.description,
    this.language,
    this.stargazersCount = 0,
    this.forksCount = 0,
    this.openIssuesCount = 0,
    this.isPrivate = false,
    this.isFork = false,
    this.isArchived = false,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String fullName;
  final String htmlUrl;
  final String ownerAvatarUrl;
  final String? description;
  final String? language;
  final int stargazersCount;
  final int forksCount;
  final int openIssuesCount;
  final bool isPrivate;
  final bool isFork;
  final bool isArchived;
  final DateTime? updatedAt;

  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;

  String get formattedStars => _compact(stargazersCount.toDouble());
  String get formattedForks => _compact(forksCount.toDouble());

  factory GitHubRepo.fromJson(Map<String, dynamic> json) => GitHubRepo(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        htmlUrl: json['html_url'] as String? ?? '',
        ownerAvatarUrl:
            ((json['owner'] as Map<String, dynamic>?)?['avatar_url'] as String?) ??
                '',
        description: json['description'] as String?,
        language: json['language'] as String?,
        stargazersCount: (json['stargazers_count'] as num?)?.toInt() ?? 0,
        forksCount: (json['forks_count'] as num?)?.toInt() ?? 0,
        openIssuesCount: (json['open_issues_count'] as num?)?.toInt() ?? 0,
        isPrivate: json['private'] as bool? ?? false,
        isFork: json['fork'] as bool? ?? false,
        isArchived: json['archived'] as bool? ?? false,
        updatedAt:
            (json['updated_at'] as String?) != null
                ? DateTime.tryParse(json['updated_at'] as String)
                : null,
      );

  static String _compact(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toInt().toString();
  }
}

/// A single entry in the user's activity feed. [type] is the raw GitHub event
/// type (e.g. `PushEvent`); [action]/[title]/[detail] carry the normalized,
/// human-readable summary extracted from the payload.
class GitHubEvent {
  const GitHubEvent({
    required this.id,
    required this.type,
    required this.repoName,
    required this.actorLogin,
    required this.actorAvatarUrl,
    this.action,
    this.title,
    this.detail,
    this.createdAt,
  });

  final String id;
  final String type;
  final String repoName;
  final String actorLogin;
  final String actorAvatarUrl;

  /// Event action such as `pushed to`, `opened`, `starred` (already merged
  /// into the summary by [summary]).
  final String? action;
  final String? title;
  final String? detail;
  final DateTime? createdAt;

  /// Short human-readable summary, e.g. "Pushed 3 commits to main" or
  /// "Opened issue #42: Crash on startup".
  String get summary {
    switch (type) {
      case 'PushEvent':
        final count = int.tryParse(detail ?? '') ?? 0;
        return 'Pushed $count commit${count == 1 ? '' : 's'} to $title';
      case 'CreateEvent':
        return 'Created ${detail ?? 'repository'} $title';
      case 'DeleteEvent':
        return 'Deleted ${detail ?? 'ref'} $title';
      case 'WatchEvent':
        return 'Starred $repoName';
      case 'ForkEvent':
        return 'Forked $repoName';
      case 'PublicEvent':
        return 'Made $repoName public';
      case 'MemberEvent':
        return '$action member in $repoName';
      case 'ReleaseEvent':
        return '$action release $title';
      case 'PullRequestEvent':
        return '$action pull request #$title';
      case 'PullRequestReviewEvent':
        return '$action review on pull request #$title';
      case 'PullRequestReviewCommentEvent':
        return '$action comment on review in $repoName';
      case 'IssuesEvent':
        return '$action issue #$title';
      case 'IssueCommentEvent':
        return '$action comment on #$title';
      case 'CommitCommentEvent':
        return 'Commented on a commit in $repoName';
      case 'GollumEvent':
        return 'Updated wiki pages in $repoName';
      default:
        return '${type.replaceAll('Event', '')} in $repoName';
    }
  }

  factory GitHubEvent.fromJson(Map<String, dynamic> json) {
    final payload = (json['payload'] as Map<String, dynamic>?) ?? const {};
    final actor = (json['actor'] as Map<String, dynamic>?) ?? const {};
    final repo = (json['repo'] as Map<String, dynamic>?) ?? const {};
    final type = json['type'] as String? ?? 'UnknownEvent';

    String? action = payload['action'] as String?;
    String? title;
    String? detail;

    switch (type) {
      case 'PushEvent':
        title = (payload['ref'] as String?)?.replaceFirst('refs/heads/', '') ?? '';
        detail = '${(payload['commits'] as List<dynamic>?)?.length ?? payload['size'] ?? 0}';
        break;
      case 'CreateEvent':
      case 'DeleteEvent':
        detail = payload['ref_type'] as String?;
        title = payload['ref'] as String? ?? '';
        break;
      case 'PullRequestEvent':
        title = '${(payload['number'] as num?)?.toInt() ?? ''}';
        detail = ((payload['pull_request'] as Map<String, dynamic>?)?['title'])
                as String? ??
            '';
        break;
      case 'PullRequestReviewEvent':
        title = '${(payload['pull_request'] as Map<String, dynamic>?)?['number'] ?? ''}';
        break;
      case 'IssuesEvent':
        title = '${(payload['issue'] as Map<String, dynamic>?)?['number'] ?? ''}';
        detail = (payload['issue'] as Map<String, dynamic>?)?['title'] as String?;
        break;
      case 'IssueCommentEvent':
      case 'PullRequestReviewCommentEvent':
        final subject = type == 'IssueCommentEvent'
            ? payload['issue'] as Map<String, dynamic>?
            : payload['pull_request'] as Map<String, dynamic>?;
        title = '${(subject?['number'] as num?)?.toInt() ?? ''}';
        detail = (payload['comment'] as Map<String, dynamic>?)?['body'] as String?;
        break;
      case 'ReleaseEvent':
        title = (payload['release'] as Map<String, dynamic>?)?['tag_name'] as String?;
        break;
      case 'MemberEvent':
        detail = (payload['member'] as Map<String, dynamic>?)?['login'] as String?;
        break;
    }

    return GitHubEvent(
      id: json['id'] as String? ?? '',
      type: type,
      repoName: repo['name'] as String? ?? '',
      actorLogin: actor['login'] as String? ?? '',
      actorAvatarUrl: actor['avatar_url'] as String? ?? '',
      action: action,
      title: (title == null || title.isEmpty) ? null : title,
      detail: (detail == null || detail.isEmpty) ? null : detail,
      createdAt:
          (json['created_at'] as String?) != null
              ? DateTime.tryParse(json['created_at'] as String)
              : null,
    );
  }
}
