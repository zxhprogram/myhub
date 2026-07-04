import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';

import '../../data/client/mail_client.dart';
import '../../data/models/mail_account_model.dart';
import '../../data/models/mail_item_model.dart';
import '../../data/repositories/mail_repository.dart';
import '../../data/services/mail_account_storage.dart';

/// A mail folder shown in the sidebar.
class MailFolder {
  const MailFolder({
    required this.id,
    required this.title,
    required this.icon,
  });

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
  MailState({MailRepository? repository})
      : _repositoryOverride = repository;

  final MailRepository? _repositoryOverride;
  MailRepository? _repository;

  final account = signal<MailAccount>(
    const MailAccount(
      emailAddress: '',
      username: '',
      password: '',
      host: '',
      port: 993,
      smtpHost: '',
      smtpPort: 587,
    ),
  );
  final hasValidAccount = signal<bool>(false);
  final configError = signal<String?>(null);

  final folders = signal<List<MailFolder>>([
    const MailFolder(id: 'INBOX', title: 'Inbox', icon: Icons.inbox),
    const MailFolder(id: 'SENT', title: 'Sent', icon: Icons.send_outlined),
    const MailFolder(id: 'DRAFTS', title: 'Drafts', icon: Icons.drafts_outlined),
    const MailFolder(id: 'TRASH', title: 'Trash', icon: Icons.delete_outlined),
    const MailFolder(id: 'SPAM', title: 'Spam', icon: Icons.report_outlined),
  ]);

  final labels = signal<List<String>>(['Work', 'Personal']);

  final selectedFolder = signal<String>('INBOX');
  final emails = signal<List<MailItem>>([]);
  final selectedEmail = signal<MailItem?>(null);
  final selectedEmailMessage = signal<MailMessage?>(null);
  final isLoading = signal<bool>(false);
  final error = signal<String?>(null);
  final searchQuery = signal<String>('');
  final unreadCounts = signal<Map<String, int>>({});

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
      await loadFolder(selectedFolder.value);
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
    _repository?.dispose();
    _repository = _repositoryOverride ?? MailRepository(account: value);
    await loadFolder(selectedFolder.value);
    return true;
  }

  String? _validate(MailAccount value) {
    if (value.emailAddress.trim().isEmpty) {
      return 'Email address is required.';
    }
    if (!value.emailAddress.contains('@') || !value.emailAddress.contains('.')) {
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
          ? await _requireRepository.fetchFolder(selectedFolder.value, forceRefresh: true)
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
      return;
    }
    selectedEmail.value = item;
    if (!item.isRead) {
      await markAsRead(item);
    }
    try {
      selectedEmailMessage.value = await _requireRepository.fetchMessage(item.uid);
    } catch (e) {
      selectedEmailMessage.value = null;
    }
  }

  Future<void> markAsRead(MailItem item) async {
    if (item.isRead) return;
    final updated = item.copyWith(isRead: true);
    emails.value = emails.value.map((e) => e.uid == item.uid ? updated : e).toList();
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

  Future<void> dispose() async {
    await _repository?.dispose();
  }
}
