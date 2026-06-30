import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({Key? key}) : super(key: key);

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  List<dynamic> _categoriesWithSources = [];
  bool _isLoading = true;
  final String _baseUrl = "http://192.168.1.125:8000/api"; 
  
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _sourceNameController = TextEditingController();
  final TextEditingController _sourceUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSources();
  }

  Future<void> _fetchSources() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse("$_baseUrl/sources"));
      if (response.statusCode == 200) {
        setState(() {
          _categoriesWithSources = json.decode(utf8.decode(response.bodyBytes));
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Помилка завантаження: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addCategory(String name) async {
    if (name.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/categories"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": name}),
      );
      if (response.statusCode == 201) {
        _categoryController.clear();
        _fetchSources();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Категорію '$name' створено")),
        );
      }
    } catch (e) {
      print("Помилка створення категорії: $e");
    }
  }

  Future<void> _addSourceToCategory(String catName, String srcName, String srcUrl) async {
    if (srcName.isEmpty || srcUrl.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/sources"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": srcName,
          "url": srcUrl,
          "category": catName,
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        _sourceNameController.clear();
        _sourceUrlController.clear();
        _fetchSources(); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Джерело додано до категорії $catName")),
        );
      }
    } catch (e) {
      print("Помилка додавання джерела: $e");
    }
  }

  Future<void> _deleteCategory(String catName) async {
    try {
      final response = await http.delete(Uri.parse("$_baseUrl/categories/$catName"));
      if (response.statusCode == 200) {
        _fetchSources();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Категорію '$catName' видалено")),
        );
      }
    } catch (e) {
      print("Помилка видалення категорії: $e");
    }
  }

  Future<void> _deleteSource(int id) async {
    try {
      final response = await http.delete(Uri.parse("$_baseUrl/sources/$id"));
      if (response.statusCode == 200) {
        _fetchSources();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Джерело видалено")),
        );
      }
    } catch (e) {
      print("Помилка видалення джерела: $e");
    }
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Нова категорія"),
        content: TextField(
          controller: _categoryController,
          decoration: const InputDecoration(hintText: "Назва (наприклад: Спорт ⚽)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Скасувати")),
          TextButton(
            onPressed: () {
              _addCategory(_categoryController.text);
              Navigator.pop(context);
            },
            child: const Text("Додати"),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog(String catName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Додати джерело в $catName"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _sourceNameController,
              decoration: const InputDecoration(hintText: "Назва (наприклад: ТСН)"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sourceUrlController,
              decoration: const InputDecoration(hintText: "RSS URL посилання"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Скасувати")),
          TextButton(
            onPressed: () {
              _addSourceToCategory(catName, _sourceNameController.text, _sourceUrlController.text);
              Navigator.pop(context);
            },
            child: const Text("Додати"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Мої Джерела Новин"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box, color: Colors.greenAccent),
            tooltip: "Створити категорію",
            onPressed: _showAddCategoryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSources,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categoriesWithSources.isEmpty
              ? const Center(child: Text("База даних порожня"))
              : ListView.builder(
                  itemCount: _categoriesWithSources.length,
                  itemBuilder: (context, index) {
                    final category = _categoriesWithSources[index];
                    final String catName = category["category_name"];
                    final List<dynamic> sources = category["sources"];

                    return Card(
                      margin: const EdgeInsets.all(10),
                      elevation: 3,
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        title: Text(
                          catName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        subtitle: Text("Джерел: ${sources.length}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [

                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                              tooltip: "Додати RSS-джерело в цю категорію",
                              onPressed: () => _showAddSourceDialog(catName),
                            ),
        
                            IconButton(
                              icon: const Icon(Icons.delete_forever, color: Colors.deepOrange),
                              tooltip: "Видалити категорію разом з джерелами",
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Видалити категорію?"),
                                    content: Text("Це видалить категорію '$catName' та всі її джерела."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Ні")),
                                      TextButton(
                                        onPressed: () {
                                          _deleteCategory(catName);
                                          Navigator.pop(context);
                                        },
                                        child: const Text("Так, видалити", style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                        children: sources.map<Widget>((src) {
                          return ListTile(
                            leading: const Icon(Icons.language, color: Colors.blue),
                            title: Text(src["name"]),
                            subtitle: Text(src["url"], maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              color: Colors.red,
                              onPressed: () => _deleteSource(src["id"]),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
    );
  }
}