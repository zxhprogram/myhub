import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';

import '../../data/client/mail_client.dart';
import '../../data/models/mail_account_model.dart';
import '../../data/models/mail_item_model.dart';
import '../../data/repositories/mail_repository.dart';

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
      : _repository = repository ??
            MailRepository(
              account: _defaultAccount,
            );

  static const _defaultAccount = MailAccount(
    host: 'imap.example.com',
    port: 993,
    username: 'demo',
    password: 'demo',
    mailbox: 'INBOX',
    useSsl: true,
  );

  final MailRepository _repository;

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

  Future<void> load() async {
    await loadFolder(selectedFolder.value);
  }

  Future<void> loadFolder(String folder) async {
    selectedFolder.value = folder;
    selectedEmail.value = null;
    selectedEmailMessage.value = null;
    isLoading.value = true;
    error.value = null;
    try {
      final query = searchQuery.value.trim();
      final result = query.isEmpty
          ? await _repository.fetchFolder(folder)
          : await _repository.search(query, folder);
      emails.value = result;
      unreadCounts.value = await _repository.getUnreadCounts();
    } on MailException catch (e) {
      error.value = e.message;
    } catch (e) {
      error.value = 'Failed to load messages: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refresh() async {
    isLoading.value = true;
    error.value = null;
    try {
      final query = searchQuery.value.trim();
      final result = query.isEmpty
          ? await _repository.fetchFolder(selectedFolder.value, forceRefresh: true)
          : await _repository.search(query, selectedFolder.value);
      emails.value = result;
      unreadCounts.value = await _repository.getUnreadCounts();
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
      selectedEmailMessage.value = await _repository.fetchMessage(item.uid);
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
      await _repository.markAsRead(item.uid);
      unreadCounts.value = await _repository.getUnreadCounts();
    } catch (e) {
      // Keep optimistic update; next refresh will reconcile.
    }
  }

  Future<void> search(String query) async {
    searchQuery.value = query;
    await loadFolder(selectedFolder.value);
  }

  Future<void> dispose() async {
    await _repository.dispose();
  }
}
