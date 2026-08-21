import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';

import '../../data/client/mail_client.dart';
import '../../data/client/mail_sender.dart';
import '../../data/models/mail_account_model.dart';
import '../../data/models/mail_item_model.dart';
import '../../data/repositories/mail_repository.dart';
import '../../data/services/mail_account_storage.dart';

/// A mail folder shown in the sidebar.
class MailFolder {
  const MailFolder({required this.id, required this.title, required this.icon});

  final String id;
  final String title;
  final IconData icon;

  MailFolder copyWith({String? id, String? title, IconData? icon}) =>
      MailFolder(
        id: id ?? this.id,
        title: title ?? this.title,
        icon: icon ?? this.icon,
      );
}

/// Signals-backed state for the mail page.
class MailState {
  MailState({MailRepository? repository}) : _repositoryOverride = repository;

  final MailRepository? _repositoryOverride;
  MailRepository? _repository;
  Timer? _initLoadTimeout;

  final account = signal<MailAccount>(
    const MailAccount(
      emailAddress: '',
      username: '',
      password: '',
      host: 'imap.qq.com',
      port: 993,
      useSsl: true,
      smtpHost: 'smtp.qq.com',
      smtpPort: 465,
      smtpUseSsl: true,
    ),
  );
  final hasValidAccount = signal<bool>(false);
  final isEditingAccount = signal<bool>(false);
  final configError = signal<String?>(null);

  final folders = signal<List<MailFolder>>([
    const MailFolder(id: 'INBOX', title: 'Inbox', icon: LucideIcons.inbox),
    const MailFolder(id: 'SENT', title: 'Sent', icon: LucideIcons.send),
    const MailFolder(
      id: 'DRAFTS',
      title: 'Drafts',
      icon: LucideIcons.mailOpen,
    ),
    const MailFolder(id: 'TRASH', title: 'Trash', icon: LucideIcons.trash2),
    const MailFolder(id: 'SPAM', title: 'Spam', icon: LucideIcons.flag),
  ]);

  final labels = signal<List<String>>(['Work', 'Personal']);

  final selectedFolder = signal<String>('INBOX');
  final emails = signal<List<MailItem>>([]);
  final selectedEmail = signal<MailItem?>(null);
  final selectedEmailMessage = signal<MailMessage?>(null);

  /// Load error for the currently selected message body, if any.
  final messageError = signal<String?>(null);

  final isLoading = signal<bool>(false);
  final error = signal<String?>(null);
  final searchQuery = signal<String>('');
  final unreadCounts = signal<Map<String, int>>({});

  final isSending = signal<bool>(false);
  final sendError = signal<String?>(null);

  /// Loads the persisted account configuration and then fetches mail if valid.
  Future<void> init() async {
    if (_repositoryOverride != null) {
      _repository = _repositoryOverride;
      hasValidAccount.value = true;
    } else {
      final saved = await MailAccountStorage.load();
      account.value = saved;
      hasValidAccount.value = saved.isValid;
      if (saved.isValid) {
        _repository = MailRepository(account: saved);
      }
    }
    if (hasValidAccount.value) {
      _initLoadTimeout?.cancel();
      _initLoadTimeout = Timer(const Duration(seconds: 30), () {
        if (isLoading.value) {
          error.value =
              'Connection timed out while loading messages. Please verify your server address, port, and password.';
          isLoading.value = false;
        }
      });
      try {
        await loadFolder(selectedFolder.value);
      } finally {
        _initLoadTimeout?.cancel();
        _initLoadTimeout = null;
      }
    }
  }

  /// Validates and saves a new account configuration.
  Future<bool> saveAccount(MailAccount value) async {
    configError.value = null;
    final validationError = _validate(value);
    if (validationError != null) {
      configError.value = validationError;
      return false;
    }
    try {
      if (_repositoryOverride == null) {
        await MailAccountStorage.save(value);
      }
    } catch (e) {
      configError.value = 'Failed to save account settings: $e';
      return false;
    }
    account.value = value;
    hasValidAccount.value = true;
    isEditingAccount.value = false;
    try {
      await _repository?.dispose().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort cleanup; continue with the new configuration.
    }
    _repository = _repositoryOverride ?? MailRepository(account: value);
    try {
      await loadFolder(
        selectedFolder.value,
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      error.value =
          'Connection timed out while loading messages. Please verify your server address, port, and password.';
      isLoading.value = false;
    }
    return true;
  }

  /// Enters account editing mode so the user can update credentials.
  void startAccountEdit() {
    isEditingAccount.value = true;
  }

  /// Exits account editing mode without saving changes.
  void cancelAccountEdit() {
    isEditingAccount.value = false;
    configError.value = null;
  }

  /// Clears the saved account and returns to the setup form.
  Future<void> signOut() async {
    if (_repositoryOverride == null) {
      await MailAccountStorage.clear();
    }
    try {
      await _repository?.dispose().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort disconnect; don't let a hung connection block sign-out.
    }
    _repository = null;
    account.value = const MailAccount(
      emailAddress: '',
      username: '',
      password: '',
      host: '',
      port: 993,
      smtpHost: '',
      smtpPort: 587,
    );
    hasValidAccount.value = false;
    isEditingAccount.value = false;
    configError.value = null;
    emails.value = [];
    selectedEmail.value = null;
    selectedEmailMessage.value = null;
    messageError.value = null;
    unreadCounts.value = {};
    error.value = null;
  }

  String? _validate(MailAccount value) {
    if (value.emailAddress.trim().isEmpty) {
      return 'Email address is required.';
    }
    if (!value.emailAddress.contains('@') ||
        !value.emailAddress.contains('.')) {
      return 'Please enter a valid email address.';
    }
    if (value.username.trim().isEmpty) {
      return 'Username is required.';
    }
    if (value.password.isEmpty) {
      return 'Password is required.';
    }
    if (value.host.trim().isEmpty) {
      return 'Incoming server (IMAP/POP3) host is required.';
    }
    if (value.port <= 0 || value.port > 65535) {
      return 'Incoming server port must be between 1 and 65535.';
    }
    if (value.smtpHost.trim().isEmpty) {
      return 'Outgoing server (SMTP) host is required.';
    }
    if (value.smtpPort <= 0 || value.smtpPort > 65535) {
      return 'Outgoing server port must be between 1 and 65535.';
    }
    return null;
  }

  Future<void> load() async {
    // When a repository override is provided but hasn't been wired up yet
    // (e.g. tests calling [load] directly without [init]), initialize it
    // lazily so the account is treated as valid.
    if (_repository == null && _repositoryOverride != null) {
      _repository = _repositoryOverride;
      hasValidAccount.value = true;
    }
    if (!hasValidAccount.value) return;
    await loadFolder(selectedFolder.value);
  }

  MailRepository get _requireRepository {
    final repo = _repository;
    if (repo == null) {
      throw StateError('Mail repository not initialized.');
    }
    return repo;
  }

  Future<void> loadFolder(String folder) async {
    if (!hasValidAccount.value) return;
    selectedFolder.value = folder;
    selectedEmail.value = null;
    selectedEmailMessage.value = null;
    messageError.value = null;
    isLoading.value = true;
    error.value = null;
    try {
      final query = searchQuery.value.trim();
      final result = query.isEmpty
          ? await _requireRepository.fetchFolder(folder)
          : await _requireRepository.search(query, folder);
      emails.value = result;
      unreadCounts.value = await _requireRepository.getUnreadCounts();
    } on MailException catch (e) {
      error.value = e.message;
    } catch (e) {
      error.value = 'Failed to load messages: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refresh() async {
    if (!hasValidAccount.value) return;
    isLoading.value = true;
    error.value = null;
    try {
      final query = searchQuery.value.trim();
      final result = query.isEmpty
          ? await _requireRepository.fetchFolder(
              selectedFolder.value,
              forceRefresh: true,
            )
          : await _requireRepository.search(query, selectedFolder.value);
      emails.value = result;
      unreadCounts.value = await _requireRepository.getUnreadCounts();
    } on MailException catch (e) {
      error.value = e.message;
    } catch (e) {
      error.value = 'Failed to refresh messages: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> retry() async {
    error.value = null;
    await load();
  }

  Future<void> selectEmail(MailItem? item) async {
    if (item == null) {
      selectedEmail.value = null;
      selectedEmailMessage.value = null;
      messageError.value = null;
      return;
    }
    selectedEmail.value = item;
    // Clear the previous body right away: rendering the stale message while
    // the next one loads wastes UI time and re-parses the old HTML.
    selectedEmailMessage.value = null;
    messageError.value = null;
    if (!item.isRead) {
      // Fire-and-forget: the optimistic local update is already applied and
      // awaiting the IMAP round-trip would delay opening the message.
      unawaited(
        markAsRead(item).catchError((Object error) {
          // Keep the optimistic update; the next refresh reconciles it.
        }),
      );
    }
    try {
      final message = await _requireRepository.fetchMessage(
        item.uid,
        folder: item.folder,
      );
      // Ignore stale responses if the user already switched to another
      // message while this one was loading.
      if (selectedEmail.value?.uid == item.uid) {
        selectedEmailMessage.value = message;
      }
    } catch (e) {
      if (selectedEmail.value?.uid == item.uid) {
        messageError.value = e is MailException
            ? e.message
            : 'Failed to load message: $e';
      }
    }
  }

  Future<void> markAsRead(MailItem item) async {
    if (item.isRead) return;
    final updated = item.copyWith(isRead: true);
    emails.value = emails.value
        .map((e) => e.uid == item.uid ? updated : e)
        .toList();
    if (selectedEmail.value?.uid == item.uid) {
      selectedEmail.value = updated;
    }
    unreadCounts.value = {
      ...unreadCounts.value,
      item.folder: (unreadCounts.value[item.folder] ?? 1) - 1,
    };
    try {
      await _requireRepository.markAsRead(item.uid);
      unreadCounts.value = await _requireRepository.getUnreadCounts();
    } catch (e) {
      // Keep optimistic update; next refresh will reconcile.
    }
  }

  Future<void> search(String query) async {
    searchQuery.value = query;
    await loadFolder(selectedFolder.value);
  }

  /// Sends an email with the given recipients, subject, and HTML body.
  /// Returns true on success, false on failure (with [sendError] set).
  Future<bool> sendMail({
    required List<String> to,
    List<String>? cc,
    required String subject,
    required String htmlBody,
    String? textBody,
  }) async {
    if (!hasValidAccount.value) {
      sendError.value = 'No mail account configured.';
      return false;
    }
    isSending.value = true;
    sendError.value = null;
    try {
      await _requireRepository.sendMail(
        to: to,
        cc: cc,
        subject: subject,
        htmlBody: htmlBody,
        textBody: textBody,
      );
      // Refresh the current folder so the sent message appears if applicable.
      await loadFolder(selectedFolder.value);
      return true;
    } on MailSendException catch (e) {
      sendError.value = e.message;
      return false;
    } catch (e) {
      sendError.value = 'Failed to send message: $e';
      return false;
    } finally {
      isSending.value = false;
    }
  }

  Future<void> dispose() async {
    _initLoadTimeout?.cancel();
    _initLoadTimeout = null;
    await _repository?.dispose();
  }
}
