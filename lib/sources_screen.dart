import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {

  List<dynamic> _categoriesWithSources = [];
  bool _isLoading = true;
  final String _baseUrl = "http://192.168.1.101:8000/api"; 
  
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _sourceNameController = TextEditingController();
  final TextEditingController _sourceUrlController = TextEditingController();

  final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       
    errorMethodCount: 5,  
    lineLength: 80,       
      ),
    );

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
      logger.e("[SOURCES SCREEN DEBUG] Error loading: $e");
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
      if (!mounted) return;

      if (response.statusCode == 201) {
        _categoryController.clear();
        _fetchSources();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Category '$name' created")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create category: ${response.statusCode}'))
        );
      }
    } catch (e) {
      if (!mounted) return;

      logger.e("[SOURCES SCREEN DEBUG] Error of creating category: $e");
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
      if (!mounted) return;

      if (response.statusCode == 201 || response.statusCode == 200) {
        _sourceNameController.clear();
        _sourceUrlController.clear();
        _fetchSources(); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Source added to category $catName")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add source to category ${response.statusCode}'))
        );
      }
    } catch (e) {
      if (!mounted) return;

      logger.e("[SOURCES SCREEN DEBUG] Error adding source: $e");
    }
  }

  Future<void> _deleteCategory(String catName) async {
    try {
      final response = await http.delete(Uri.parse("$_baseUrl/categories/$catName"));
      if (!mounted) return;

      if (response.statusCode == 200) {
        _fetchSources();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Category '$catName' deleted")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete categoty ${response.statusCode}'))
        );
      }
    } catch (e) {
      if (!mounted) return;
      logger.e("[SOURCES SCREEN DEBUG] Error deleting category: $e");
    }
  }

  Future<void> _deleteSource(int id) async {
    try {
      final response = await http.delete(Uri.parse("$_baseUrl/sources/$id"));
      if (!mounted) return;

      if (response.statusCode == 200) {
        _fetchSources();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Source deleted")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete source ${response.statusCode}'))
        );
      }
    } catch (e) {
      if (!mounted) return;
      logger.e("[SOURCES SCREEN DEBUG] Error deleting source: $e");
    }
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New category"),
        content: TextField(
          controller: _categoryController,
          decoration: const InputDecoration(hintText: "Name (e.g., Sports ⚽)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              _addCategory(_categoryController.text);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog(String catName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add source to $catName"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _sourceNameController,
              decoration: const InputDecoration(hintText: "Name (e.g., TSN)"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sourceUrlController,
              decoration: const InputDecoration(hintText: "RSS URL link"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              _addSourceToCategory(catName, _sourceNameController.text, _sourceUrlController.text);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My sources"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box, color: Colors.greenAccent),
            tooltip: "Create category",
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
              ? const Center(child: Text("Database is empty"))
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
                        subtitle: Text("Sources: ${sources.length}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [

                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                              tooltip: "Add RSS source to this category",
                              onPressed: () => _showAddSourceDialog(catName),
                            ),
        
                            IconButton(
                              icon: const Icon(Icons.delete_forever, color: Colors.deepOrange),
                              tooltip: "Delete category with all sources",
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Delete category?"),
                                    content: Text("This will delete the category '$catName' and all its sources."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
                                      TextButton(
                                        onPressed: () {
                                          _deleteCategory(catName);
                                          Navigator.pop(context);
                                        },
                                        child: const Text("Yes, delete", style: TextStyle(color: Colors.red)),
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