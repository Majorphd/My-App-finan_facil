// main.dart (versão sem Firebase)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  tz.initializeTimeZones();
  await initNotifications();
  runApp(const FinanFacilApp());
}

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: android);
  await notificationsPlugin.initialize(initSettings);
  scheduleReminder();
}

void scheduleReminder() async {
  await notificationsPlugin.zonedSchedule(
    0,
    'Lembrete FinanFácil',
    'Já registrou suas despesas hoje?',
    tz.TZDateTime.now(tz.local).add(const Duration(hours: 12)),
    const NotificationDetails(
      android: AndroidNotificationDetails('daily_reminder', 'Lembretes Diários'),
    ),
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

class Expense {
  final String descricao;
  final double valor;
  final DateTime data;
  final String categoria;

  Expense({required this.descricao, required this.valor, required this.data, required this.categoria});

  Map<String, dynamic> toJson() => {
        'descricao': descricao,
        'valor': valor,
        'data': data.toIso8601String(),
        'categoria': categoria,
      };

  static Expense fromJson(Map<String, dynamic> json) => Expense(
        descricao: json['descricao'],
        valor: json['valor'],
        data: DateTime.parse(json['data']),
        categoria: json['categoria'],
      );
}

class ExpenseStorage {
  static const _key = 'expenses';

  static Future<void> saveExpenses(List<Expense> expenses) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(expenses.map((e) => e.toJson()).toList());
    await prefs.setString(_key, jsonString);
  }

  static Future<List<Expense>> loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString == null) return [];
    final List list = jsonDecode(jsonString);
    return list.map((e) => Expense.fromJson(e)).toList();
  }
}

class FinanFacilApp extends StatelessWidget {
  const FinanFacilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinanFácil',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<Expense> _expenses = [];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    final loaded = await ExpenseStorage.loadExpenses();
    setState(() => _expenses.addAll(loaded));
  }

  void _addExpense(Expense e) {
    setState(() => _expenses.add(e));
    ExpenseStorage.saveExpenses(_expenses);
  }

  void _clearExpenses() {
    setState(() => _expenses.clear());
    ExpenseStorage.saveExpenses([]);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildResumo(),
      AddExpenseScreen(onSave: _addExpense),
      _buildHistorico()
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('FinanFácil')),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Resumo'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Adicionar'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Histórico'),
        ],
      ),
    );
  }

  Widget _buildResumo() {
    final total = _expenses.fold(0.0, (acumulado, e) => acumulado + e.valor);
    return Column(
      children: [
        const SizedBox(height: 16),
        Text('Total: R\$ ${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 16),
        Expanded(child: _buildPieChart(_expenses)),
      ],
    );
  }

  Widget _buildPieChart(List<Expense> expenses) {
    final total = expenses.fold(0.0, (acumulado, e) => acumulado + e.valor);
    return PieChart(
      PieChartData(
        sections: expenses.map((e) {
          final percent = (e.valor / total) * 100;
          return PieChartSectionData(
            value: e.valor,
            title: '${percent.toStringAsFixed(1)}%',
            color: Colors.primaries[expenses.indexOf(e) % Colors.primaries.length],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistorico() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _expenses.length,
            itemBuilder: (context, index) {
              final e = _expenses[index];
              return Card(
                child: ListTile(
                  title: Text(e.descricao),
                  subtitle: Text('${e.categoria} - ${DateFormat('dd/MM/yyyy').format(e.data)}'),
                  trailing: Text('R\$ ${e.valor.toStringAsFixed(2)}'),
                ),
              );
            },
          ),
        ),
        ElevatedButton(onPressed: _clearExpenses, child: const Text('Limpar Histórico')),
      ],
    );
  }
}

class AddExpenseScreen extends StatefulWidget {
  final Function(Expense) onSave;
  const AddExpenseScreen({super.key, required this.onSave});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = 'Alimentação';

  void _saveExpense() {
    if (_descriptionController.text.isEmpty || _amountController.text.isEmpty) return;
    final valor = double.tryParse(_amountController.text) ?? 0.0;
    if (valor <= 0) return;
    final nova = Expense(
      descricao: _descriptionController.text,
      valor: valor,
      data: DateTime.now(),
      categoria: _selectedCategory,
    );
    widget.onSave(nova);
    _descriptionController.clear();
    _amountController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Despesa salva!')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Descrição')),
          TextField(controller: _amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor')),
          DropdownButtonFormField(
            value: _selectedCategory,
            items: ['Alimentação', 'Transporte', 'Lazer', 'Outros']
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (val) => setState(() => _selectedCategory = val!),
            decoration: const InputDecoration(labelText: 'Categoria'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _saveExpense, child: const Text('Salvar')),
        ],
      ),
    );
  }
}
